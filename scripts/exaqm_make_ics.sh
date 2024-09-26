#!/bin/bash

set -x

msg="JOB $job HAS BEGUN"
postmsg "$msg"

export pgm=aqm_make_ics
#-----------------------------------------------------------------------
#
# Source the variable definitions file and the bash utility functions.
#
#-----------------------------------------------------------------------
#
. $USHaqm/source_util_funcs.sh


$SRWrun/chgres_cube.py \
   -c &GLOBAL_VAR_DEFNS_FP; \
   --cycle @Y-@m-@dT@H:@M:@S \
   --key-path task_make_ics

export err=$?; err_chk
if [ -e "${pgmout}" ]; then
   cat ${pgmout}
fi
#
#-----------------------------------------------------------------------
#
# Move initial condition, surface, control, and 0-th hour lateral bound-
# ary files to ICs_BCs directory.
#
#-----------------------------------------------------------------------
#
#
mv out.atm.tile7.nc \
        ${COMIN}/${cyc}/${NET}.${cycle}.gfs_data.tile7.halo0.nc

mv out.sfc.tile7.nc \
        ${COMIN}/${cyc}/${NET}.${cycle}.sfc_data.tile7.halo0.nc

mv gfs_ctrl.nc ${COMIN}/${cyc}/${NET}.${cycle}.gfs_ctrl.nc

mv gfs.bndy.nc ${COMIN}/${cyc}/${NET}.${cycle}.gfs_bndy.tile7.f000.nc
#
#-----------------------------------------------------------------------
#
# Set up the RESTART folder for AQM runs
#
#-----------------------------------------------------------------------

if [ "${DO_REAL_TIME}" == "TRUE" ] && [ "${CPL_AQM}" == "TRUE" ]; then

  export yyyy=$(echo $PDY | cut -c1-4)
  export mm=$(echo $PDY | cut -c5-6)
  export dd=$(echo $PDY | cut -c7-8)

  case ${cyc} in
   00) rst_dir1=${COMINm1}/18/RESTART
       rst_file1=fv_tracer.res.tile1.nc
       fv_tracer_file1=${rst_dir1}/${PDY}.${cyc}0000.${rst_file1}
       rst_dir2=${COMINm1}/12/RESTART
       rst_file2=fv_tracer.res.tile1.nc
       fv_tracer_file2=${rst_dir2}/${PDY}.${cyc}0000.${rst_file2}
       ;;
   06)
       rst_dir1=${COMIN}/00/RESTART
       rst_file1=fv_tracer.res.tile1.nc
       fv_tracer_file1=${rst_dir1}/${PDY}.${cyc}0000.${rst_file1}
       rst_dir2=${COMINm1}/12/RESTART
       rst_file2=fv_tracer.res.tile1.nc
       fv_tracer_file2=${rst_dir2}/${PDY}.${cyc}0000.${rst_file2}
       ;;
   12)
       rst_dir1=${COMIN}/06/RESTART
       rst_file1=fv_tracer.res.tile1.nc
       fv_tracer_file1=${rst_dir1}/${PDY}.${cyc}0000.${rst_file1}
       rst_dir2=${COMINm1}/12/RESTART
       rst_file2=fv_tracer.res.tile1.nc
       fv_tracer_file2=${rst_dir2}/${PDY}.${cyc}0000.${rst_file2}
       ;;
   18)
       rst_dir1=${COMIN}/12/RESTART
       rst_file1=fv_tracer.res.tile1.nc
       fv_tracer_file1=${rst_dir1}/${PDY}.${cyc}0000.${rst_file1}
       rst_dir2=${COMIN}/06/RESTART
       rst_file2=fv_tracer.res.tile1.nc
       fv_tracer_file2=${rst_dir2}/${PDY}.${cyc}0000.${rst_file2}
       ;;
  esac

  rst_dir_fix=${HOMEaqm}/fix/restart
  rst_file_fix=fv_tracer.res.tile1.nc
  fv_tracer_file_fix=${rst_dir_fix}/${rst_file_fix}

  print_info_msg "
  Looking for tracer restart file: \"${fv_tracer_file1}\""

  if [ -d ${rst_dir1} ]; then
    if [ -s ${fv_tracer_file1} ]; then
      print_info_msg "
      Tracer file found: \"${fv_tracer_file1}\""
    elif [ -s ${fv_tracer_file2} ]; then
      print_info_msg "
      Tracer file: \"${fv_tracer_file1}\" not found."
      print_info_msg "
      Instead using tracer file: \"${fv_tracer_file2}\""
      cpreq ${fv_tracer_file2} ${fv_tracer_file1}
      cpreq ${rst_dir2}/${PDY}.${cyc}0000.coupler.res  ${rst_dir1}/
    else
      print_info_msg "
      Both tracer files: \"${fv_tracer_file1}\" and
      \"${fv_tracer_file2}\" not found."
      print_info_msg "
      Instead using dummy tracer file: \"${fv_tracer_file_fix}\""
      cpreq ${fv_tracer_file_fix} ${fv_tracer_file1}
      cpreq ${rst_dir_fix}/coupler.res  ${rst_dir1}
      sed -i "s/yyyy/$yyyy/g" ${rst_dir1}/coupler.res
      sed -i "s/mm/$mm/g" ${rst_dir1}/coupler.res
      sed -i "s/dd/$dd/g" ${rst_dir1}/coupler.res
      sed -i "s/hh/${cyc}/g" ${rst_dir1}/coupler.res
      mv ${rst_dir1}/coupler.res ${rst_dir1}/${PDY}.${cyc}0000.coupler.res
    fi 
  elif [ -s ${fv_tracer_file2} ]; then
    mkdir -p ${rst_dir1}
    cpreq ${fv_tracer_file2} ${fv_tracer_file1} 
    cpreq ${rst_dir2}/${PDY}.${cyc}0000.coupler.res  ${rst_dir1}/
    print_info_msg "
    Tracer file: \"${fv_tracer_file1}\" not found."
    print_info_msg "
    Instead using tracer file: \"${fv_tracer_file2}\""
  else
    mkdir -p ${rst_dir1}
    print_info_msg "
    Both tracer files: \"${fv_tracer_file1}\" and
    \"${fv_tracer_file2}\" not found."
    print_info_msg "
    Instead using dummy tracer file: \"${fv_tracer_file_fix}\""
    cpreq ${fv_tracer_file_fix} ${fv_tracer_file1}
    cpreq ${rst_dir_fix}/coupler.res  ${rst_dir1}
    sed -i "s/yyyy/$yyyy/g" ${rst_dir1}/coupler.res
    sed -i "s/mm/$mm/g" ${rst_dir1}/coupler.res
    sed -i "s/dd/$dd/g" ${rst_dir1}/coupler.res
    sed -i "s/hh/${cyc}/g" ${rst_dir1}/coupler.res
    mv  ${rst_dir1}/coupler.res ${rst_dir1}/${PDY}.${cyc}0000.coupler.res
  fi
fi

