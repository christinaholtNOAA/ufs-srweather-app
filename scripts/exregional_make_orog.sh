#!/usr/bin/env bash

#
#-----------------------------------------------------------------------
#
# This ex-script is responsible for creating orography files for the FV3
# forecast.
#
# The output of this script is placed in a directory defined by OROG_DIR
#
# More about the orog for the regional configuration of the FV3:
#
#    a) Only the tile 7 orography file is created.
#
#    b) This orography file contains a halo of the same width (NHW)
#       as the grid file for tile 7 generated by the make_grid script
#
#    c) Filtered versions of the orogoraphy files are created with the
#       same width (NHW) as the unfiltered orography file and the grid
#       file. FV3 requires two filtered orography files, one with no
#       halo cells and one with 4 halo cells.
#
# This script does the following:
#
#   - Create the raw orography files by running the orog executable.
#   - Run the orog_gsl executable if any of several GSL-developed
#     physics suites is chosen by the user.
#   - Run the filter_topo executable on the raw orography files
#   - Run the shave executable for the 0- and 4-cell halo orography
#     files
#
# Run-time environment variables:
#
#   DATA
#   GLOBAL_VAR_DEFNS_FP
#   REDIRECT_OUT_ERR
#
# Experiment variables
#
#  user:
#    EXECdir
#    USHdir
#
#  platform:
#    FIXorg
#    PRE_TASK_CMDS
#    RUN_CMD_SERIAL
#
#  workflow:
#    CCPP_PHYS_SUITE
#    CRES
#    DOT_OR_USCORE
#    FIXam
#    FIXlam
#    GRID_GEN_METHOD
#    PREEXISTING_DIR_METHOD
#    VERBOSE
#
#  task_make_orog:
#    KMP_AFFINITY_MAKE_OROG
#    OMP_NUM_THREADS_MAKE_OROG
#    OMP_STACKSIZE_MAKE_OROG
#    OROG_DIR
#
#  task_make_grid:
#    GFDLgrid_NUM_CELLS
#    GFDLgrid_STRETCH_FAC
#    GFDLgrid_REFINE_RATIO
#
#  constants:
#    NH0
#    NH4
#    TILE_RGNL
#
#  grid_params:
#    NHW
#    NX
#    NY
#    STRETCH_FAC
#
#-----------------------------------------------------------------------
#

#
#-----------------------------------------------------------------------
#
# Source the variable definitions file and the bash utility functions.
#
#-----------------------------------------------------------------------
#
. $USHdir/source_util_funcs.sh
sections=(
  user
  nco
  platform
  workflow
  constants
  grid_params
  task_make_grid
  task_make_orog
)
for sect in ${sections[*]} ; do
  source_yaml ${GLOBAL_VAR_DEFNS_FP} ${sect}
done

#
#-----------------------------------------------------------------------
#
# Save current shell options (in a global array).  Then set new options
# for this script/function.
#
#-----------------------------------------------------------------------
#
{ save_shell_opts; . $USHdir/preamble.sh; } > /dev/null 2>&1
#
#-----------------------------------------------------------------------
#
# Get the full path to the file in which this script/function is located 
# (scrfunc_fp), the name of that file (scrfunc_fn), and the directory in
# which the file is located (scrfunc_dir).
#
#-----------------------------------------------------------------------
#
scrfunc_fp=$( $READLINK -f "${BASH_SOURCE[0]}" )
scrfunc_fn=$( basename "${scrfunc_fp}" )
scrfunc_dir=$( dirname "${scrfunc_fp}" )

print_info_msg "
========================================================================
Entering script:  \"${scrfunc_fn}\"
In directory:     \"${scrfunc_dir}\"

This is the ex-script for the task that generates orography files.
========================================================================"
#
#-----------------------------------------------------------------------
#
# Set OpenMP variables.  The orog executable runs with OMP.
#
#-----------------------------------------------------------------------
#
export KMP_AFFINITY=${KMP_AFFINITY_MAKE_OROG}
export OMP_NUM_THREADS=${OMP_NUM_THREADS_MAKE_OROG}
export OMP_STACKSIZE=${OMP_STACKSIZE_MAKE_OROG}

eval ${PRE_TASK_CMDS}

if [ -z "${RUN_CMD_SERIAL:-}" ] ; then
  print_err_msg_exit "\
  Run command was not set in machine file. \
  Please set RUN_CMD_SERIAL for your platform"
else
  print_info_msg "$VERBOSE" "
  All executables will be submitted with command \'${RUN_CMD_SERIAL}\'."
fi
#
#-----------------------------------------------------------------------
#
# Create the (cycle-independent) subdirectories under the experiment
# directory (EXPTDIR) that are needed by the various steps and substeps
# in this script.
#
#-----------------------------------------------------------------------
#
check_for_preexist_dir_file "${OROG_DIR}" "${PREEXISTING_DIR_METHOD}"
mkdir -p "${OROG_DIR}"

raw_dir="${OROG_DIR}/raw_topo"
mkdir -p "${raw_dir}"

filter_dir="${OROG_DIR}/filtered_topo"
mkdir -p "${filter_dir}"

shave_dir="${OROG_DIR}/shave_tmp"
mkdir -p "${shave_dir}"
#
#
#-----------------------------------------------------------------------
#
# Preparatory steps before calling raw orography generation code.
#
#-----------------------------------------------------------------------
#
exec_fn="orog"
exec_fp="$EXECdir/${exec_fn}"
if [ ! -f "${exec_fp}" ]; then
  print_err_msg_exit "\
The executable (exec_fp) for generating the orography file does not exist:
  exec_fp = \"${exec_fp}\"
Please ensure that you've built this executable."
fi

DATA="${DATA:-${raw_dir}/tmp}"
mkdir -p "${DATA}"
cd "${DATA}"
#
# Copy topography and related data files from the system directory (FIXorg)
# to the temporary directory.
#
cp ${FIXorg}/thirty.second.antarctic.new.bin fort.15
cp ${FIXorg}/landcover30.fixed .
cp ${FIXorg}/gmted2010.30sec.int fort.235
#
#-----------------------------------------------------------------------
#
# Get the grid file info from the mosaic file
#
#-----------------------------------------------------------------------
#
mosaic_fn="${CRES}${DOT_OR_USCORE}mosaic.halo${NHW}.nc"
mosaic_fp="${FIXlam}/${mosaic_fn}"

grid_fn=$( get_charvar_from_netcdf "${mosaic_fp}" "gridfiles" ) || print_err_msg_exit "\
  get_charvar_from_netcdf function failed."
grid_fp="${FIXlam}/${grid_fn}"
#
#-----------------------------------------------------------------------
#
# Set input parameters for the orog executable in a formatted text file.
# The executable takes its parameters via the command line.
#
# Note: lonb and latb are placeholders in this case since the program
# uses the ones obtained from the grid file.
#
#-----------------------------------------------------------------------
#
mtnres=1
lonb=0
latb=0
jcap=0
NR=0
NF1=0
NF2=0
efac=0
blat=0

input_redirect_fn="INPS"
orogfile="none"

echo $mtnres $lonb $latb $jcap $NR $NF1 $NF2 $efac $blat > "${input_redirect_fn}"
#
# The following two inputs are read in as strings, so they must be quoted
# in the input file.
#
echo "\"${grid_fp}\"" >> "${input_redirect_fn}"
echo "\"$orogfile\"" >> "${input_redirect_fn}"
echo ".false." >> "${input_redirect_fn}" #MASK_ONLY
echo "none" >> "${input_redirect_fn}" #MERGE_FILE
cat "${input_redirect_fn}"
#
#-----------------------------------------------------------------------
#
# Call the executable to generate the raw orography file corresponding
# to tile 7 (the regional domain) only.
#
# The script moves the output file from its temporary directory to the
# OROG_DIR and names it:
#
#   ${CRES}_raw_orog.tile7.halo${NHW}.nc
#
# Note that this file will include orography for a halo of width NHW
# cells around tile 7.
#
#-----------------------------------------------------------------------
#
print_info_msg "$VERBOSE" "\
Starting orography file generation..."

PREP_STEP
eval ${RUN_CMD_SERIAL} "${exec_fp}" < "${input_redirect_fn}"  ${REDIRECT_OUT_ERR} || \
      print_err_msg_exit "\
Call to executable (exec_fp) that generates the raw orography file returned
with nonzero exit code:
  exec_fp = \"${exec_fp}\""
POST_STEP

#
# Change location to the original directory.
#
cd -
#
#-----------------------------------------------------------------------
#
# Move the raw orography file and rename it.
#
#-----------------------------------------------------------------------
#
raw_orog_fp_orig="${DATA}/out.oro.nc"
raw_orog_fn_prefix="${CRES}${DOT_OR_USCORE}raw_orog"
fn_suffix_with_halo="tile${TILE_RGNL}.halo${NHW}.nc"
raw_orog_fn="${raw_orog_fn_prefix}.${fn_suffix_with_halo}"
raw_orog_fp="${raw_dir}/${raw_orog_fn}"
mv "${raw_orog_fp_orig}" "${raw_orog_fp}"
#
#-----------------------------------------------------------------------
#
# Call the orog_gsl executable to generate the two orography statistics
# files (large- and small-scale) needed for the drag suite in certain
# GSL physics suites.
#
#-----------------------------------------------------------------------
#
suites=( "FV3_RAP" "FV3_HRRR" "FV3_GFS_v15_thompson_mynn_lam3km" "FV3_GFS_v17_p8" )
if [[ ${suites[@]} =~ "${CCPP_PHYS_SUITE}" ]] ; then
  DATA="${DATA:-${OROG_DIR}/temp_orog_data}"
  mkdir -p ${DATA}
  cd ${DATA}
  mosaic_fn_gwd="${CRES}${DOT_OR_USCORE}mosaic.halo${NH4}.nc"
  mosaic_fp_gwd="${FIXlam}/${mosaic_fn_gwd}"
  grid_fn_gwd=$( get_charvar_from_netcdf "${mosaic_fp_gwd}" "gridfiles" ) || \
    print_err_msg_exit "get_charvar_from_netcdf function failed."
  grid_fp_gwd="${FIXlam}/${grid_fn_gwd}"
  ls_fn="geo_em.d01.lat-lon.2.5m.HGT_M.nc"
  ss_fn="HGT.Beljaars_filtered.lat-lon.30s_res.nc"
  create_symlink_to_file ${grid_fp_gwd} ${DATA}/${grid_fn_gwd} TRUE
  create_symlink_to_file ${FIXam}/${ls_fn} ${DATA}/${ls_fn} TRUE
  create_symlink_to_file ${FIXam}/${ss_fn} ${DATA}/${ss_fn} TRUE

  input_redirect_fn="grid_info.dat"
  cat > "${input_redirect_fn}" <<EOF
${TILE_RGNL}
${CRES:1}
${NH4}
EOF

  exec_fn="orog_gsl"
  exec_fp="$EXECdir/${exec_fn}"
  if [ ! -f "${exec_fp}" ]; then
    print_err_msg_exit "\
The executable (exec_fp) for generating the GSL orography GWD data files
does not exist:
  exec_fp = \"${exec_fp}\"
Please ensure that you've built this executable."
  fi

  print_info_msg "$VERBOSE" "
Starting orography file generation..."

  PREP_STEP
  eval ${RUN_CMD_SERIAL} "${exec_fp}" < "${input_redirect_fn}"  ${REDIRECT_OUT_ERR} || \
      print_err_msg_exit "\
Call to executable (exec_fp) that generates the GSL orography GWD data files
returned with nonzero exit code:
  exec_fp = \"${exec_fp}\""
  POST_STEP

  mv "${CRES}${DOT_OR_USCORE}oro_data_ss.tile${TILE_RGNL}.halo${NH0}.nc" \
     "${CRES}${DOT_OR_USCORE}oro_data_ls.tile${TILE_RGNL}.halo${NH0}.nc" \
     "${OROG_DIR}"
 
fi
#
#-----------------------------------------------------------------------
#
# Note that the orography filtering code assumes that the regional grid
# is a GFDLgrid type of grid; it is not designed to handle ESGgrid type
# regional grids.  If the flag "regional" in the orography filtering
# namelist file is set to .TRUE. (which it always is will be here; see
# below), then filtering code will first calculate a resolution (i.e.
# number of grid points) value named res_regional for the assumed GFDLgrid
# type regional grid using the formula
#
#   res_regional = res*stretch_fac*real(refine_ratio)
#
# Here res, stretch_fac, and refine_ratio are the values passed to the
# code via the namelist.  res and stretch_fac are assumed to be the
# resolution (in terms of number of grid points) and the stretch factor
# of the (GFDLgrid type) regional grid's parent global cubed-sphere grid,
# and refine_ratio is the ratio of the number of grid cells on the regional
# grid to a single cell on tile 6 of the parent global grid.  After
# calculating res_regional, the code interpolates/extrapolates between/
# beyond a set of (currently 7) resolution values for which the four
# filtering parameters (n_del2_weak, cd4, max_slope, peak_fac) are provided
# (by GFDL) to obtain the corresponding values of these parameters at a
# resolution of res_regional.  These interpolated/extrapolated values are
# then used to perform the orography filtering.
#
# To handle ESGgrid type grids, we set res in the namelist to the
# orography filtering code the equivalent global uniform cubed-sphere
# resolution of the regional grid, we set stretch_fac to 1 (since the
# equivalent resolution assumes a uniform global grid), and we set
# refine_ratio to 1.  This will cause res_regional above to be set to
# the equivalent global uniform cubed-sphere resolution, so the
# filtering parameter values will be interpolated/extrapolated to that
# resolution value.
#
#-----------------------------------------------------------------------
#
if [ "${GRID_GEN_METHOD}" = "GFDLgrid" ]; then

# Note:
# It is also possible to use the equivalent global uniform cubed-sphere
# resolution when filtering on a GFDLgrid type grid by setting the namelist
# parameters as follows:
#
#  res="${CRES:1}"
#  stretch_fac="1" (or "0.999" if "1" makes it crash)
#  refine_ratio="1"
#
# Really depends on what EMC wants to do.

  res="${GFDLgrid_NUM_CELLS}"
  refine_ratio="${GFDLgrid_REFINE_RATIO}"

elif [ "${GRID_GEN_METHOD}" = "ESGgrid" ]; then

  res="${CRES:1}"
  refine_ratio="1"

fi
#
# Set the name and path to the executable and make sure that it exists.
#
exec_fn="filter_topo"
exec_fp="$EXECdir/${exec_fn}"
if [ ! -f "${exec_fp}" ]; then
  print_err_msg_exit "\
The executable (exec_fp) for filtering the raw orography does not exist:
  exec_fp = \"${exec_fp}\"
Please ensure that you've built this executable."
fi
#
# The filter_topo program overwrites its input file with filtered
# output, which is specified by topo_file in the namelist, but with a
# suffix ".tile7.nc" for the regional configuration. To avoid
# overwriting the output of the orog program, copy its output file to
# the filter_topo working directory and rename it. Here, the name is
# chosen such that it:
#
# (1) indicates that it contains filtered orography data (because that
#     is what it will contain once the orography filtering executable
#     successfully exits); and
# (2) ends with the string ".tile${N}.nc" expected by the orography
#     filtering code.
#
fn_suffix_without_halo="tile${TILE_RGNL}.nc"
filtered_orog_fn_prefix="${CRES}${DOT_OR_USCORE}filtered_orog"
filtered_orog_fp_prefix="${filter_dir}/${filtered_orog_fn_prefix}"
filtered_orog_fp="${filtered_orog_fp_prefix}.${fn_suffix_without_halo}"
cp "${raw_orog_fp}" "${filtered_orog_fp}"
#
# The filter_topo program looks for the grid file specified
# in the mosaic file (more specifically, specified by the gridfiles
# variable in the mosaic file) in its own run directory. Make a symlink
# to it.
#
create_symlink_to_file ${grid_fp} ${filter_dir}/${grid_fn} TRUE
#
# Create the namelist file (in the filter_dir directory) that the orography
# filtering executable will read in.
#
# Note that in the namelist file for the orography filtering code (created
# later below), the mosaic file name is saved in a variable called
# "grid_file".  It would have been better to call this "mosaic_file"
# instead so it doesn't get confused with the grid file for a given tile.
cat > "${filter_dir}/input.nml" <<EOF
&filter_topo_nml
  grid_file = "${mosaic_fp}"
  topo_file = "${filtered_orog_fp_prefix}"
  mask_field = "land_frac"
  regional = .true.
  stretch_fac = ${STRETCH_FAC}
  res = $res
/
EOF
#
# Change location to the filter dir directory to run. The executable
# expects to find its input.nml file in the directory from which it is
# run.
#
cd "${filter_dir}"
#
# Run the orography filtering executable.
#
print_info_msg "$VERBOSE" "
Starting filtering of orography..."

PREP_STEP
eval ${RUN_CMD_SERIAL} "${exec_fp}" ${REDIRECT_OUT_ERR} || \
  print_err_msg_exit "\
Call to executable that generates filtered orography file returned with
non-zero exit code."
POST_STEP
#
# For clarity, rename the filtered orography file in filter_dir
# such that its new name contains the halo size.
#
filtered_orog_fn_orig=$( basename "${filtered_orog_fp}" )
filtered_orog_fn="${filtered_orog_fn_prefix}.${fn_suffix_with_halo}"
filtered_orog_fp=$( dirname "${filtered_orog_fp}" )"/${filtered_orog_fn}"
mv "${filtered_orog_fn_orig}" "${filtered_orog_fn}"
#
# Change location to the original directory.
#
cd -

print_info_msg "$VERBOSE" "
Filtering of orography complete."
#
#-----------------------------------------------------------------------
#
# Partially "shave" the halo from the (filtered) orography file having a
# wide halo to generate two new orography files -- one without a halo and
# another with a 4-cell-wide halo.  These are needed as inputs by the
# surface climatology file generation code (sfc_climo; if it is being
# run), the initial and boundary condition generation code (chgres_cube),
# and the forecast model.
#
#-----------------------------------------------------------------------
#
# Set the name and path to the executable and make sure that it exists.
#
exec_fn="shave"
exec_fp="$EXECdir/${exec_fn}"
if [ ! -f "${exec_fp}" ]; then
  print_err_msg_exit "\
The executable (exec_fp) for \"shaving\" down the halo in the orography
file does not exist:
  exec_fp = \"${exec_fp}\"
Please ensure that you've built this executable."
fi

unshaved_fp="${filtered_orog_fp}"
#
# We perform the work in shave_dir, so change location to that directory.
# Once it is complete, we move the resultant file from shave_dir to OROG_DIR.
#
cd "${shave_dir}"
#
# Create an input config file for the shave executable to generate an
# orography file without a halo from the one with a wide halo.  Then call
# the shave executable.  Finally, move the resultant file to the OROG_DIR
# directory.
#
print_info_msg "$VERBOSE" "
\"Shaving\" filtered orography file with a ${NHW}-cell-wide halo to obtain
a filtered orography file with a ${NH0}-cell-wide halo..."

ascii_fn="input.shave.orog.halo${NH0}"
shaved_fp="${shave_dir}/${CRES}${DOT_OR_USCORE}oro_data.tile${TILE_RGNL}.halo${NH0}.nc"
printf "%s %s %s %s %s\n" \
  $NX $NY ${NH0} \"${unshaved_fp}\" \"${shaved_fp}\" \
  > ${ascii_fn}

PREP_STEP
eval ${RUN_CMD_SERIAL} ${exec_fp} < ${ascii_fn} ${REDIRECT_OUT_ERR} || \
print_err_msg_exit "\
Call to executable (exec_fp) to generate a (filtered) orography file with
a ${NH0}-cell-wide halo from the orography file with a {NHW}-cell-wide halo
returned with nonzero exit code:
  exec_fp = \"${exec_fp}\"
The config file (ascii_fn) used in this call is in directory shave_dir:
  ascii_fn = \"${ascii_fn}\"
  shave_dir = \"${shave_dir}\""
POST_STEP
mv ${shaved_fp} ${OROG_DIR}
#
# Create an input config file for the shave executable to generate an
# orography file with a 4-cell-wide halo from the one with a wide halo.
# Then call the shave executable.  Finally, move the resultant file to
# the OROG_DIR directory.
#
print_info_msg "$VERBOSE" "
\"Shaving\" filtered orography file with a ${NHW}-cell-wide halo to obtain
a filtered orography file with a ${NH4}-cell-wide halo..."

ascii_fn="input.shave.orog.halo${NH4}"
shaved_fp="${shave_dir}/${CRES}${DOT_OR_USCORE}oro_data.tile${TILE_RGNL}.halo${NH4}.nc"
printf "%s %s %s %s %s\n" \
  $NX $NY ${NH4} \"${unshaved_fp}\" \"${shaved_fp}\" \
  > ${ascii_fn}

PREP_STEP
eval ${RUN_CMD_SERIAL} ${exec_fp} < ${ascii_fn} ${REDIRECT_OUT_ERR} || \
print_err_msg_exit "\
Call to executable (exec_fp) to generate a (filtered) orography file with
a ${NH4}-cell-wide halo from the orography file with a {NHW}-cell-wide halo
returned with nonzero exit code:
  exec_fp = \"${exec_fp}\"
The namelist file (ascii_fn) used in this call is in directory shave_dir:
  ascii_fn = \"${ascii_fn}\"
  shave_dir = \"${shave_dir}\""
POST_STEP
mv "${shaved_fp}" "${OROG_DIR}"
#
# Change location to the original directory.
#
cd -
#
#-----------------------------------------------------------------------
#
# Add link in OROG_DIR directory to the orography file with a 4-cell-wide
# halo such that the link name does not contain the halo width.  These links
# are needed by the make_sfc_climo task.
#
# NOTE: It would be nice to modify the sfc_climo_gen_code to read in
# files that have the halo size in their names.
#
#-----------------------------------------------------------------------
#
python3 $USHdir/link_fix.py \
  --path-to-defns ${GLOBAL_VAR_DEFNS_FP} \
  --file-group "orog" || \
print_err_msg_exit "\
Call to function to create links to orography files failed."

print_info_msg "
========================================================================
Orography files with various halo widths generated successfully!!!

Exiting script:  \"${scrfunc_fn}\"
In directory:    \"${scrfunc_dir}\"
========================================================================"
#
#-----------------------------------------------------------------------
#
# Restore the shell options saved at the beginning of this script/func-
# tion.
#
#-----------------------------------------------------------------------
#
{ restore_shell_opts; } > /dev/null 2>&1


