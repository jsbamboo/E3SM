#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

program prim_main
#ifdef _PRIM
  use prim_driver_mod, only : prim_init1, prim_init2, prim_finalize, prim_run_subcycle
  use hybvcoord_mod, only : hvcoord_t, hvcoord_init
#endif

  use parallel_mod,     only: parallel_t, initmp, syncmp, haltmp, abortmp
  use hybrid_mod,       only: hybrid_t
  use thread_mod,       only: nthreads, hthreads, vthreads, omp_get_thread_num, &
                              omp_set_num_threads, omp_get_nested, &
                              omp_get_num_threads, omp_get_max_threads
  use time_mod,         only: tstep, nendstep, timelevel_t, TimeLevel_init, nstep=>nextOutputStep
  use dimensions_mod,   only: nelemd, qsize
  use control_mod,      only: restartfreq, vfile_mid, vfile_int, runtype
  use domain_mod,       only: domain1d_t
  use element_mod,      only: element_t
  use common_io_mod,    only: output_dir, infilenames
  use common_movie_mod, only: nextoutputstep
  use perf_mod,         only: t_initf, t_prf, t_finalizef, t_startf, t_stopf, t_disablef, t_enablef ! _EXTERNAL
  use restart_io_mod ,  only: restartheader_t, writerestart
  use hybrid_mod,       only: hybrid_create
#if (defined MODEL_THETA_L && defined ARKODE)
  use arkode_mod,       only: calc_nonlinear_stats, finalize_nonlinear_stats
#endif
#ifdef HOMME_ENABLE_COMPOSE
  use compose_test_mod, only: compose_test
#endif
  use test_mod,         only: print_test_results

#ifdef PIO_INTERP
  use interp_movie_mod, only : interp_movie_output, interp_movie_finish, interp_movie_init
  use interpolate_driver_mod, only : interpolate_driver, pio_read_phis
#else
  use prim_movie_mod,   only : prim_movie_output, prim_movie_finish,prim_movie_init
  use interpolate_driver_mod, only : pio_read_phis
#endif

  implicit none

#if defined(HOMMEXX_BFB_TESTING) && !KOKKOS_TARGET
  interface
    subroutine initialize_kokkos_f90() bind(c)
    end subroutine initialize_kokkos_f90

    subroutine finalize_kokkos_f90() bind(c)
    end subroutine finalize_kokkos_f90
  end interface
#endif

  type (element_t),  pointer  :: elem(:)
  type (hybrid_t)             :: hybrid         ! parallel structure for shared memory/distributed memory
  type (parallel_t)           :: par            ! parallel structure for distributed memory programming
  type (domain1d_t), pointer  :: dom_mt(:)
  type (RestartHeader_t)      :: RestartHeader
  type (TimeLevel_t)          :: tl             ! Main time level struct
  type (hvcoord_t)            :: hvcoord        ! hybrid vertical coordinate struct

  real*8 timeit, et, st
  integer nets,nete
  integer ithr
  integer ierr
  
  character (len=20) :: numproc_char
  character (len=20) :: numtrac_char
  
  logical :: dir_e ! boolean existence of directory where output netcdf goes
  logical :: call_enablef
  
  ! =====================================================
  ! Begin executable code set distributed memory world...
  ! =====================================================
  par=initmp()

#if defined(HOMMEXX_BFB_TESTING) && !KOKKOS_TARGET
  call initialize_kokkos_f90();
#endif

  ! =====================================
  ! Set number of threads...
  ! =====================================
  if(par%masterproc) print *,"Primitive Equation Init1..."
  call t_initf('input.nl',LogPrint=par%masterproc, &
               Mpicom=par%comm, MasterTask=par%masterproc)
  call t_startf('Total')
  call t_startf('prim_init1')
  call prim_init1(elem,  par,dom_mt,tl)
  call t_stopf('prim_init1')

  ! =====================================
  ! Begin threaded region so each thread can print info
  ! =====================================
#if (defined HORIZ_OPENMP && defined COLUMN_OPENMP)
#ifndef __bg__
   if (vthreads>1 .and. (.not. omp_get_nested())) then
     call haltmp("Nested threading required but not available. Set OMP_NESTED=true")
   endif
#endif
#endif

  ! =====================================
  ! Begin threaded region so each thread can print info
  ! =====================================
#if (defined HORIZ_OPENMP)
  !$OMP PARALLEL NUM_THREADS(hthreads), DEFAULT(SHARED), PRIVATE(ithr,nets,nete,hybrid)
  call omp_set_num_threads(vthreads)
#endif
  ithr=omp_get_thread_num()
  nets=dom_mt(ithr)%start
  nete=dom_mt(ithr)%end
  ! ================================================
  ! Initialize thread decomposition
  ! Note: The OMP Critical is required for threading since the Fortran 
  !   standard prohibits multiple I/O operations on the same unit.
  ! ================================================
#if (defined HORIZ_OPENMP)
  !$OMP CRITICAL
#endif
  if (par%rank<100) then 
     write(6,9) par%rank,ithr,omp_get_max_threads(),nets,nete 
  endif
9 format("process: ",i2,1x,"horiz thread id: ",i2,1x,"# vert threads: ",i2,1x,&
       "element limits: ",i5,"-",i5)
#if (defined HORIZ_OPENMP)
  !$OMP END CRITICAL
  !$OMP END PARALLEL
#endif
  
  ! setup fake threading so we can call routines that require 'hybrid'
  ithr=omp_get_thread_num()
  hybrid = hybrid_create(par,ithr,1)
  nets=1
  nete=nelemd


  ! ==================================
  ! Initialize the vertical coordinate  (cam initializes hvcoord externally)
  ! ==================================
  hvcoord = hvcoord_init(vfile_mid, vfile_int, .true., hybrid%masterthread, ierr)
  if (ierr /= 0) then
     call haltmp("error in hvcoord_init")
  end if



  ! this should really be called from test_mod.F90, but it has be be called outside
  ! the threaded region
  if (infilenames(1)/='') then
     if (index(infilenames(1),"np4pg")==0) then
        call pio_read_phis(elem,hybrid%par,"PHIS")
     else
        call pio_read_phis(elem,hybrid%par,"PHIS_d")
     endif
  endif

  if(par%masterproc) print *,"Primitive Equation Initialization..."
#if (defined HORIZ_OPENMP)
  !$OMP PARALLEL NUM_THREADS(hthreads), DEFAULT(SHARED), PRIVATE(ithr,nets,nete,hybrid)
  call omp_set_num_threads(vthreads)
#endif
  ithr=omp_get_thread_num()
  hybrid = hybrid_create(par,ithr,hthreads)
  nets=dom_mt(ithr)%start
  nete=dom_mt(ithr)%end

  if(hybrid%masterthread) print *,"Primitive Equation Init2..."
  call t_startf('prim_init2')
  call prim_init2(elem, hybrid,nets,nete,tl, hvcoord)
  call t_stopf('prim_init2')
#if (defined HORIZ_OPENMP)
  !$OMP END PARALLEL
#endif


  ! Here we get sure the directory specified
  ! in the input namelist file in the 
  ! variable 'output_dir' does exist.
  ! this avoids a abort deep within the PIO 
  ! library (SIGABRT:signal 6) which in most
  ! architectures produces a core dump.
  if (par%masterproc) then 
     open(unit=447,file=trim(output_dir) // "/output_dir_test",iostat=ierr)
     if ( ierr==0 ) then
        print *,'Directory ',trim(output_dir), ' does exist: initialing IO'
        close(447)
     else
        print *,'Error creating file in directory ',trim(output_dir)
        call abortmp("Please be sure the directory exist or specify 'output_dir' in the namelist.")
     end if
  endif
#if 0
  this ALWAYS fails on lustre filesystems.  replaced with the check above
  inquire( file=output_dir, exist=dir_e )
  if ( dir_e ) then
     if(par%masterproc) print *,'Directory ',output_dir, ' does exist: initialing IO'
  else
     if(par%masterproc) print *,'Directory ',output_dir, ' does not exist: stopping'
     call abortmp("Please get sure the directory exist or specify one via output_dir in the namelist file.")
  end if
#endif
  
  if(par%masterproc) print *,"I/O init..."
! initialize history files.  filename constructed with restart time
! so we have to do this after ReadRestart in prim_init2 above
  call t_startf('prim_io_init')
#if defined PIO_INTERP
  call interp_movie_init( elem, par,  hvcoord, tl )
#else
  call prim_movie_init( elem, par, hvcoord, tl )
#endif
  call t_stopf('prim_io_init')

  ! output initial state for NEW runs (not restarts or branch runs)
  if (runtype == 0 ) then
     if(par%masterproc) print *,"Output of initial state..."
#if defined PIO_INTERP
     call interp_movie_output(elem, tl, par, 0d0, hvcoord=hvcoord)
#else
     call prim_movie_output(elem, tl, hvcoord, par)
#endif
  endif

#ifdef HOMME_ENABLE_COMPOSE
  call compose_test(par, hvcoord, dom_mt, elem)
#endif

  if(par%masterproc) print *,"Entering main timestepping loop"
  call t_startf('prim_main_loop')
  call_enablef = .false.
  do while(tl%nstep < nEndStep)
#ifdef DISABLE_TIMERS_IN_FIRST_STEP
     ! Certain compilers, e.g., for Intel GPU, do just-in-time compilation. Turn
     ! off timers in the first step to avoid counting that cost.
     if (tl%nstep == 0) then
        call t_disablef()
        call_enablef = .true.
     elseif (call_enablef) then
        call t_enablef()
        call_enablef = .false.
     end if
#endif

#if (defined HORIZ_OPENMP)
     !$OMP PARALLEL NUM_THREADS(hthreads), DEFAULT(SHARED), PRIVATE(ithr,nets,nete,hybrid)
     call omp_set_num_threads(vthreads)
#endif
     ithr=omp_get_thread_num()
     hybrid = hybrid_create(par,ithr,hthreads)
     nets=dom_mt(ithr)%start
     nete=dom_mt(ithr)%end
     
     nstep = nextoutputstep(tl)
     do while(tl%nstep<nstep)
        call t_startf('prim_run')
        call prim_run_subcycle(elem, hybrid,nets,nete, tstep, .false., tl, hvcoord,1)
        call t_stopf('prim_run')
     end do
#if (defined HORIZ_OPENMP)
     !$OMP END PARALLEL
#endif

#if defined PIO_INTERP
     call interp_movie_output(elem, tl, par, 0d0,hvcoord=hvcoord)
#else
     call prim_movie_output(elem, tl, hvcoord, par)
#endif

     ! ============================================================
     ! Write restart files if required 
     ! ============================================================
     if(restartfreq > 0) then
         if (MODULO(tl%nstep,restartfreq) ==0) call WriteRestart(elem,ithr,1,nelemd,tl)
     endif
  end do !end of while tl%nstep < nEndStep
  call t_stopf('prim_main_loop')

  if(par%masterproc) print *,"Finished main timestepping loop",tl%nstep
  call prim_finalize()
  if(par%masterproc) print *,"closing history files"

  call print_test_results(elem, tl, hvcoord, par)

#if defined PIO_INTERP
  call interp_movie_finish
#else
  call prim_movie_finish
#endif

#if (defined MODEL_THETA_L && defined ARKODE)
  if (calc_nonlinear_stats) then
    call finalize_nonlinear_stats(par%comm, par%rank, par%root, par%nprocs)
  endif
#endif

#if defined(HOMMEXX_BFB_TESTING) && !KOKKOS_TARGET
  call finalize_kokkos_f90();
#endif


  call t_stopf('Total')
  if(par%masterproc) print *,"writing timing data"
  call t_prf('HommeTime', par%comm)
  if(par%masterproc) print *,"calling t_finalizef"
  call t_finalizef()
  call haltmp("exiting program...")
end program prim_main
