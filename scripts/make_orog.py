"""
The run script for making the orography files for the experiment.
"""

import glob
import logging
import os
import sys
from argparse import ArgumentParser
from pathlib import Path

from uwtools.api.filter_topo import FilterTopo
from uwtools.api.orog import Orog
from uwtools.api.orog_gsl import OrogGSL
from uwtools.api.shave import Shave
from uwtools.api.config import get_yaml_config

logger = logging.getLogger()
logger.setLevel(logging.DEBUG)

parser = ArgumentParser(
    description="Script that runs the make_grid task via uwtools API",
)
parser.add_argument(
    "-c",
    "--config-file",
    metavar="PATH",
    required=True,
    help="Path to experiment config file.",
    type=Path,
)
parser.add_argument(
    "--key-path",
    help="Dot-separated path of keys leading through the config to the tasks's YAML block",
    metavar="KEY[.KEY...]",
    required=True,
)

args = parser.parse_args()
expt_config = get_yaml_config(args.config_file)
make_orog_config = get_yaml_config(expt_config[args.key_path])
task_rundir = Path(make_orog_config["rundir"])
print(f"Will run make_orog in {task_rundir}")

CRES = expt_config["workflow"]["CRES"]
os.environ["CRES"] = CRES

KEY_PATH = args.key_path.split(".")
fix_lam_path = Path(expt_config["workflow"]["FIXlam"])

# Run orog
orog_driver = Orog(
    config=args.config_file,
    key_path=[args.key_path],
)
rundir = Path(orog_driver.config["rundir"])
print(f"Will run orog in {rundir}")
orog_driver.run()

if not (rundir / "runscript.orog.done").is_file():
    print("Error occurred running orog. Please see component error logs.")
    sys.exit(1)

# Run orog_gsl if using GSL's orography drag suite
ccpp_phys_suite = expt_config["workflow"]["CCPP_PHYS_SUITE"]
orog_drag_suites = [
    "FV3_RAP",
    "FV3_HRRR",
    "FV3_GFS_v15_thompson_mynn_lam3km",
    "FV3_GFS_v17_p8",
]
if ccpp_phys_suite in orog_drag_suites:
    orog_gsl_driver = OrogGSL(
        config=args.config_file,
        key_path=[args.key_path],
    )
    rundir = Path(orog_gsl_driver.config["rundir"])
    print(f"Will run orog_gsl in {rundir}")
    orog_gsl_driver.run()

    if not (rundir / "runscript.orog_gsl.done").is_file():
        print("Error occurred running orog_gsl. Please see component error logs.")
        sys.exit(1)

    output_files = [
        f"{CRES}_oro_data_ss.tile7.halo0.nc",
        f"{CRES}_oro_data_ls.tile7.halo0.nc",
    ]
    for ofile in output_files:
        path = rundir / ofile
        linkname = fix_lam_path / path.name
        if linkname.is_symlink():
            linkname.unlink()
        linkname.symlink_to(path)


# Run filter_topo
filter_topo_driver = FilterTopo(
    config=args.config_file,
    key_path=KEY_PATH,
)
rundir = Path(filter_topo_driver.config["rundir"])
print(f"Will run filter_topo_driver in {rundir}")
filter_topo_driver.run()

if not (rundir / "runscript.filter_topo.done").is_file():
    print("Error occurred running filter_topo. Please see component error logs.")
    sys.exit(1)

# Run shave for 0- and 4-cell-wide halo
for sub_path in ["shave0", "shave4"]:
    key_path = KEY_PATH + [sub_path]
    shave_driver = Shave(
        config=args.config_file,
        key_path=key_path,
    )
    rundir = Path(shave_driver.config["rundir"])
    print(f"Will run {sub_path} in {rundir}")
    shave_driver.run()
    if not (rundir / "runscript.shave.done").is_file():
        print(f"Error occurred running {sub_path}. Please see component error logs.")
        sys.exit(1)

# Link shave output to fix directory
for fpath in glob.glob(str(task_rundir / f"{CRES}*.nc")):
    path = Path(fpath)
    linkname = fix_lam_path / path.name
    if linkname.is_symlink():
        linkname.unlink()
    linkname.symlink_to(path)

Path(task_rundir / "make_orog_task_complete.txt").touch()
