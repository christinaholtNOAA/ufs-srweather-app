#!/bin/bash

#
#-----------------------------------------------------------------------
#
# The ex-script that stages initial and boundary conditions for the
# analysis and model for the current cycle. The initial conditions could
# come from an external model or a forecast from a previous cycles.  The
# boundary conditions could come from any of several previous cycles.
#
#-----------------------------------------------------------------------
#
#-----------------------------------------------------------------------
#
# Source the variable definitions file and the bash utility functions.
#
#-----------------------------------------------------------------------
#
. $USHdir/source_util_funcs.sh
source_config_for_task "task_prepare_analysis_input" ${GLOBAL_VAR_DEFNS_FP}

#
#-----------------------------------------------------------------------
#
# Save current shell options (in a global array).  Then set new options
# for this script/function.
#
#-----------------------------------------------------------------------
#
{ save_shell_opts; . $USHdir/preamble.sh; } > /dev/null 2>&1

print_info_msg "
========================================================================
Entering script:  \"${scrfunc_fn}\"
In directory:     \"${scrfunc_dir}\"

This is the ex-script for the task that prepares the analysis input for
the specified cycle.
========================================================================"

#
#-----------------------------------------------------------------------
#
# prepare initial conditions for 
#     warm start if BKTYPE=0
#     cold start if BKTYPE=1
#     spinupcyc + warm start if BKTYPE=2
#       the previous 6 cycles are searched to find the restart files
#       valid at this time from the closest previous cycle.
#
# Note: Only BKTYPE=0 is supported at this time.
#-----------------------------------------------------------------------
#
BKTYPE=0


#
#-----------------------------------------------------------------------
#
# Cycle the surface fields
#     warm start if SFC_CYC=0
#     cold start if SFC_CYC=1
#     delayed surface cycle if SFC_CYC=2
#     skip surface cycling and do soil surgery if SFC_CYC=3
#
# Note: Only SFC_CYC=0 is supported at this time.
#-----------------------------------------------------------------------
#
SFC_CYC=0


cd_vrfy ${modelinputdir}

fg_restart_dirname=fcst_fv3lam

restart_prefix="${YYYYMMDD}.${HH}0000."

# Check any of the previous cycles in the past 6 hours for restart files.
for prev in $(seq $DA_CYCLE_INTERV $DA_CYCLE_INTERV 6) ; do
  YYYYMMDDHHmInterv=$( date +%Y%m%d%H -d "${START_DATE} ${prev} hours ago" )
  bkpath=${fg_root}/${YYYYMMDDHHmInterv}${SLASH_ENSMEM_SUBDIR}/${fg_restart_dirname}/RESTART

  print_info_msg "$VERBOSE" "Trying this path: ${bkpath}"

  checkfile=${bkpath}/${restart_prefix}coupler.res
  if [ -r "${checkfile}" ] ; then
    print_info_msg "$VERBOSE" "Found ${checkfile}; Use it as background for analysis "
    # Found a file, stop searching
    break
  fi
done

filelistn="fv_core.res.tile1.nc \
  fv_srf_wnd.res.tile1.nc \
  fv_tracer.res.tile1.nc \
  phy_data.nc \
  sfc_data.nc"

n_io_layout_y=$(($IO_LAYOUT_Y-1))
list_io_layout=$(seq 0 $n_io_layout_y)

# Copy background files because they will be updated. Link background
# files under a different name so we can see analysis increments easily.
if [ -r ${checkfile} ] ; then

  cp_vrfy $checkfile bk_coupler.res
  cp_vrfy ${bkpath}/${restart_prefix}fv_core.res.nc fv_core.res.nc

  # remove checksum from restart files. Checksum will cause trouble if
  # model initializes from analysis
  ncatted -a checksum,,d,, fv_core.res.nc

  if [ "${IO_LAYOUT_Y}" == "1" ]; then
    for file in ${filelistn}; do
      cp_vrfy ${bkpath}/${restart_prefix}${file} ${file}
      ln_vrfy -s ${bkpath}/${restart_prefix}${file} bk_${file}

      # remove checksum from restart files. Checksum will cause trouble if
      # model initializes from analysis
      ncatted -a checksum,,d,, ${file}
    done
    ncatted -O -a source,global,c,c,'FV3GFS GAUSSIAN NETCDF FILE' fv_core.res.tile1.nc
  else
    for file in ${filelistn}; do
      for ii in $list_iolayout
      do
        iii=$(printf %4.4i $ii)
        cp_vrfy ${bkpath}/${restart_prefix}${file}.${iii} ${file}.${iii}
        ln_vrfy -s ${bkpath}/${restart_prefix}${file}.${iii} bk_${file}.${iii}

        # remove checksum from restart files. Checksum will cause trouble if
        # model initializes from analysis
        ncatted -a checksum,,d,, ${file}.${iii}
      done
      ncatted -O -a source,global,c,c,'FV3GFS GAUSSIAN NETCDF FILE' fv_core.res.tile1.nc.${iii}
    done
  fi

  # generate coupler.res with right date
  head -1 bk_coupler.res > coupler.res
  tail -1 bk_coupler.res >> coupler.res
  tail -1 bk_coupler.res >> coupler.res

else
  print_err_msg_exit "Error: cannot find background: ${checkfile}"
fi

cp_vrfy ${fg_root}/${YYYYMMDDHHmInterv}${SLASH_ENSMEM_SUBDIR}/${fg_restart_dirname}/INPUT/gfs_ctrl.nc  gfs_ctrl.nc


#-----------------------------------------------------------------------
#
# do snow/ice update at ${SNOWICE_update_hour}z for the restart
# sfc_data.nc
#
#-----------------------------------------------------------------------

snow_files="latest.SNOW_IMS \
  ${YYJJJ2200000000} \
  rap.${YYYYMMDD}/rap.t${HH}z.imssnow.grib2 \
  rap.${YYYYMMDD}/rap_e.t${HH}z.imssnow.grib2"

latest_snow_file="latest.SNOW_IMS"

if [ ${HH} -eq ${SNOWICE_update_hour} ] && [ ${cycle_type} == "prod" ] ; then

  # Find the best latest snow file
  for snow_file in $snow_files ; do
    if [ -r ${IMSSNOW_ROOT}/$snow_file ] ; then
      cp_vrfy ${IMSSNOW_ROOT}/$snow_file $latest_snow_file
      break
    fi
  done

  if [ ! -f $latest_snow_file ] ; then
    echo "${IMSSNOW_ROOT} data does not exist!!"
    echo "ERROR: No snow update at ${HH}!!!!"
  fi

  if [ -r $latest_snow_file ] ; then
    ln_vrfy -sf ./latest.SNOW_IMS imssnow2

    if [ "${IO_LAYOUT_Y}" == "1" ]; then
      ln_vrfy -sf ${FIX_GSI}/${PREDEF_GRID_NAME}/fv3_grid_spec fv3_grid_spec
    else
      for ii in ${list_iolayout}
      do
        iii=$(printf %4.4i $ii)
        ln_vrfy -sf ${gridspec_dir}/fv3_grid_spec.${iii} fv3_grid_spec.${iii}
      done
    fi

    snowice_exec_fn="process_imssnow_fv3lam.exe"
    snowice_exec_fp="$EXECDIR/${snowice_exec_fn}"

    if [ ! -f "${snowice_exec_fp}" ]; then
      print_err_msg_exit "\
The executable (snowice_exec_fn) for processing snow/ice data onto FV3-LAM
native grid does not exist:
  snowice_exec_fp= \"${snowice_exec_fp}\"
Please ensure that you have built this executable."
    fi

    cp_vrfy ${snowice_exec_fp} .

    eval $RUN_CMD_PREPARE_ANALYSIS_INPUT ./${snowice_exec_fn} ${IO_LAYOUT_Y} || \
     print_err_msg_exit "\
 Call to executable (fvcom_exe) to modify sfc fields for FV3-LAM failed:
   snowice_exe = \"${snowice_exec_fp}\"
 The following variables were being used:
   list_iolayout = \"${list_iolayout}\""

else
 echo "NOTE: No update for SST at ${YYYYMMDDHH}!"
fi

#-----------------------------------------------------------------------
#
# do SST update at ${SST_update_hour}z for the restart sfc_data.nc
#
#-----------------------------------------------------------------------


