include (ScreamUtils)

set (TEST_BASE_NAME mam4_srf_online_emiss_standalone)
set (FIXTURES_BASE_NAME ${TEST_BASE_NAME}_generate_output_nc_files)

# Create the test
CreateADUnitTest(${TEST_BASE_NAME}
  LABELS mam4_srf_online_emiss physics
  LIBS mam
  MPI_RANKS ${TEST_RANK_START} ${TEST_RANK_END}
  FIXTURES_SETUP_INDIVIDUAL ${FIXTURES_BASE_NAME}
)

# Set AD configurable options
set (ATM_TIME_STEP 1800)
SetVarDependingOnTestSize(NUM_STEPS 2 5 48)  # 1h 2.5h 24h
set (RUN_T0 2021-10-12-45000)

## Copy (and configure) yaml files needed by tests
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/input.yaml
               ${CMAKE_CURRENT_BINARY_DIR}/input.yaml)
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/output.yaml
               ${CMAKE_CURRENT_BINARY_DIR}/output.yaml)

# Ensure test input files are present in the data dir
GetInputFile(scream/init/${EAMxx_tests_IC_FILE_MAM4xx_72lev})

# Ensure test input files are present in the data dir
set (TEST_INPUT_FILES
  scream/mam4xx/emissions/ne2np4/surface/DMSflux.2010.ne2np4_conserv.POPmonthlyClimFromACES4BGC_c20240726.nc
  scream/mam4xx/emissions/ne2np4/surface/cmip6_mam4_so2_surf_ne2np4_2010_clim_c20240723.nc
  scream/mam4xx/emissions/ne2np4/surface/cmip6_mam4_bc_a4_surf_ne2np4_2010_clim_c20240726.nc
  scream/mam4xx/emissions/ne2np4/surface/cmip6_mam4_num_a1_surf_ne2np4_2010_clim_c20240726.nc
  scream/mam4xx/emissions/ne2np4/surface/cmip6_mam4_num_a2_surf_ne2np4_2010_clim_c20240726.nc
  scream/mam4xx/emissions/ne2np4/surface/cmip6_mam4_num_a4_surf_ne2np4_2010_clim_c20240726.nc
  scream/mam4xx/emissions/ne2np4/surface/cmip6_mam4_pom_a4_surf_ne2np4_2010_clim_c20240726.nc
  scream/mam4xx/emissions/ne2np4/surface/cmip6_mam4_so4_a1_surf_ne2np4_2010_clim_c20240726.nc
  scream/mam4xx/emissions/ne2np4/surface/cmip6_mam4_so4_a2_surf_ne2np4_2010_clim_c20240726.nc
  scream/mam4xx/emissions/ne2np4/dst_ne2np4_c20241028.nc
  scream/mam4xx/emissions/ne2np4/monthly_macromolecules_0.1deg_bilinear_year01_merge_ne2np4_c20241030.nc
)
foreach (file IN ITEMS ${TEST_INPUT_FILES})
  GetInputFile(${file})
endforeach()

# Compare output files produced by npX tests, to ensure they are bfb
include (CompareNCFiles)

CompareNCFilesFamilyMpi (
  TEST_BASE_NAME ${TEST_BASE_NAME}
  FILE_META_NAME ${TEST_BASE_NAME}_output.INSTANT.nsteps_x1.npMPIRANKS.${RUN_T0}.nc
  MPI_RANKS ${TEST_RANK_START} ${TEST_RANK_END}
  LABELS mam4_srf_online_emiss physics
  META_FIXTURES_REQUIRED ${FIXTURES_BASE_NAME}_npMPIRANKS_omp1
)

if (SCREAM_ENABLE_BASELINE_TESTS)
  # Compare one of the output files with the baselines.
  # Note: one is enough, since we already check that np1 is BFB with npX
  set (OUT_FILE ${TEST_BASE_NAME}_output.INSTANT.nsteps_x1.np${TEST_RANK_END}.${RUN_T0}.nc)
  CreateBaselineTest(${TEST_BASE_NAME} ${TEST_RANK_END} ${OUT_FILE} ${FIXTURES_BASE_NAME}) 
endif()
