include(ExternalProject)

ExternalProject_Add(UFS_UTILS
  PREFIX ${CMAKE_CURRENT_BINARY_DIR}/UFS_UTILS
  SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/UFS_UTILS
  INSTALL_DIR ${CMAKE_INSTALL_PREFIX}
  CMAKE_ARGS "-DCMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX}"
  )

if(NOT CCPP_SUITES)
  set(CCPP_SUITES "rrfs_gfsv16,FV3_GFS_v15_thompson_mynn,nssl_mp_no_nsst")
endif()

ExternalProject_Add(ufs_weather_model
  PREFIX ${CMAKE_CURRENT_BINARY_DIR}/ufs_weather_model
  SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/ufs_weather_model
  INSTALL_DIR ${CMAKE_INSTALL_PREFIX}
  CMAKE_ARGS   "-DCMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX}"
               "-DCCPP_SUITES=${CCPP_SUITES}"
               "-DCMAKE_C_COMPILER=${MPI_C_COMPILER}"
               "-DCMAKE_CXX_COMPILER=${MPI_CXX_COMPILER}"
               "-DCMAKE_Fortran_COMPILER=${MPI_Fortran_COMPILER}"
               "-DSTATIC=Y"
               "-DNETCDF_DIR=$ENV{NETCDF}"
               "-DAPP=ATM"
  INSTALL_COMMAND mkdir -p ${CMAKE_INSTALL_PREFIX}/bin && cp ${CMAKE_CURRENT_BINARY_DIR}/ufs_weather_model/src/ufs_weather_model-build/ufs_model ${CMAKE_INSTALL_PREFIX}/bin/
  )
