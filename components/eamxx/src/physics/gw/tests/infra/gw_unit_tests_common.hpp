#ifndef GW_UNIT_TESTS_COMMON_HPP
#define GW_UNIT_TESTS_COMMON_HPP

#include "share/eamxx_types.hpp"
#include "share/util/eamxx_setup_random_test.hpp"
// #include "gw_functions.hpp"
// #include "gw_data.hpp"
#include "ekat/util/ekat_test_utils.hpp"
#include "gw_test_data.hpp"

#include <vector>
#include <sstream>

namespace scream {
namespace gw {
namespace unit_test {

/*
 * Unit test infrastructure for gw unit tests.
 *
 * gw entities can friend scream::gw::unit_test::UnitWrap to give unit tests
 * access to private members.
 *
 * All unit test impls should be within an inner struct of UnitWrap::UnitTest for
 * easy access to useful types.
 */

struct UnitWrap {

  enum BASELINE_ACTION {
    NONE,
    COMPARE,
    GENERATE
  };

  template <typename D=DefaultDevice>
  struct UnitTest : public KokkosTypes<D> {

    using Device      = D;
    using MemberType  = typename KokkosTypes<Device>::MemberType;
    using TeamPolicy  = typename KokkosTypes<Device>::TeamPolicy;
    using RangePolicy = typename KokkosTypes<Device>::RangePolicy;
    using ExeSpace    = typename KokkosTypes<Device>::ExeSpace;

    template <typename S>
    using view_1d = typename KokkosTypes<Device>::template view_1d<S>;
    template <typename S>
    using view_2d = typename KokkosTypes<Device>::template view_2d<S>;
    template <typename S>
    using view_3d = typename KokkosTypes<Device>::template view_3d<S>;

    template <typename S>
    using uview_1d = typename ekat::template Unmanaged<view_1d<S> >;

    using Functions          = scream::gw::Functions<Real, Device>;
    // using view_ice_table     = typename Functions::view_ice_table;
    // using view_collect_table = typename Functions::view_collect_table;
    // using view_1d_table      = typename Functions::view_1d_table;
    // using view_2d_table      = typename Functions::view_2d_table;
    // using view_dnu_table     = typename Functions::view_dnu_table;
    using Scalar             = typename Functions::Scalar;
    using Spack              = typename Functions::Spack;
    // using Pack               = typename Functions::Pack;
    // using IntSmallPack       = typename Functions::IntSmallPack;
    // using Smask              = typename Functions::Smask;
    // using TableIce           = typename Functions::TableIce;
    // using TableRain          = typename Functions::TableRain;
    // using Table3             = typename Functions::Table3;
    // using C                  = typename Functions::C;

    static constexpr Int max_pack_size = 16;
    static constexpr Int num_test_itrs = max_pack_size / Spack::n;

    struct Base {
      std::string     m_baseline_path;
      std::string     m_test_name;
      BASELINE_ACTION m_baseline_action;
      ekat::FILEPtr   m_fid;

      Base() :
        m_baseline_path(""),
        m_test_name(Catch::getResultCapture().getCurrentTestName()),
        m_baseline_action(NONE),
        m_fid()
      {
        //Functions::gw_init(); // many tests will need table data
        auto& ts = ekat::TestSession::get();
        if (ts.flags["c"]) {
          m_baseline_action = COMPARE;
        }
        else if (ts.flags["g"]) {
          m_baseline_action = GENERATE;
        }
        else if (ts.flags["n"]) {
          m_baseline_action = NONE;
        }
        m_baseline_path = ts.params["b"];

        EKAT_REQUIRE_MSG( !(m_baseline_action != NONE && m_baseline_path == ""),
                          "GW unit test flags problem: baseline actions were requested but no baseline path was provided");

        std::string baseline_name = m_baseline_path + "/" + m_test_name;
        if (m_baseline_action == COMPARE) {
          m_fid = ekat::FILEPtr(fopen(baseline_name.c_str(), "r"));
        }
        else if (m_baseline_action == GENERATE) {
          m_fid = ekat::FILEPtr(fopen(baseline_name.c_str(), "w"));
        }
      }

      ~Base() {}

      std::mt19937_64 get_engine()
      {
        if (m_baseline_action != COMPARE) {
          // We can use any seed
          int seed;
          auto engine = setup_random_test(nullptr, &seed);
          if (m_baseline_action == GENERATE) {
            // Write the seed
            ekat::write(&seed, 1, m_fid);
          }
          return engine;
        }
        else {
          // Read the seed
          int seed;
          ekat::read(&seed, 1, m_fid);
          return setup_random_test(seed);
        }
      }
    };

    // Put struct decls here
    struct TestGwdComputeTendenciesFromStressDivergence;
  }; // UnitWrap
};

} // namespace unit_test
} // namespace gw
} // namespace scream

#endif
