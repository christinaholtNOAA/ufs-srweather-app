#!/usr/bin/env python
"""
The run script for run_fcst 
"""

import datetime as dt
import logging
import os
import re
import sys
from argparse import ArgumentParser
from copy import deepcopy
from pathlib import Path

from uwtools.api.logging import use_uwtools_logger
from uwtools.api.fv3 import FV3
from uwtools.api.config import get_yaml_config


def link_files(dest_dir, files):
    """
    Link a given list of files to the destination directory using the same file names.
    """
    for fpath in files:
        path = Path(fpath)
        linkname = dest_dir / path.name
        if linkname.is_symlink():
            linkname.unlink()
        logging.info(f"Linking {linkname} -> {path}")
        linkname.symlink_to(path)

def parse_args(argv):
    """
    Parse arguments for the script.
    """
    parser = ArgumentParser(
        description="Script that runs FV3 via uwtools API.",
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
        "--cycle",
        help="The cycle in ISO8601 format (e.g. 2024-07-15T18).",
        required=True,
        type=dt.datetime.fromisoformat,
    )
    parser.add_argument(
        "--key-path",
        help="Dot-separated path of keys leading through the config to the driver's YAML block.",
        metavar="KEY[.KEY...]",
        required=True,
        type=lambda s: s.split("."),
    )
    parser.add_argument(
        "--member",
        default="000",
        help="The 3-digit ensemble member number.",
    )
    return parser.parse_args(argv)


def run_fcst(config_file, cycle, key_path, member):
    """
    Setup and run the FV3 Driver.
    """
    expt_config = get_yaml_config(config_file)

    # The experiment config will have {{ CRES | env }} and {{ MEMBER | env }} expressions in it that need to be
    # dereferenced during driver initialization
    os.environ["CRES"] = expt_config["workflow"]["CRES"]
    os.environ["DOT_ENSMEM"] = f".mem{member}"
    os.environ["MEMBER"] = member

    # Run the FV3 program via UW driver
    fv3_driver = FV3(
        config=config_file,
        cycle=cycle,
        key_path=key_path,
    )
    rundir = Path(fv3_driver.config["rundir"])
    logging.info(f"Will run FV3 in {rundir}")
    fv3_driver.run()

    if not (rundir / "runscript.fv3.done").is_file():
        logging.error("Error occurred running FV3. Please see component error logs.")
        sys.exit(1)

    # Deliver output data to a common location above the rundir.
    fix_lam_path = Path(expt_config["workflow"]["FIXlam"])

    # Link output data to fix directory
    _link_files(
        dest_dir=fix_lam_path,
        files=glob.glob(str(rundir / f"*.nc")),
    )

    # Mark the successful completion of the script on disk
    Path(task_rundir / "run_fcst_task_complete.txt").touch()


if __name__ == "__main__":

    use_uwtools_logger()

    args = parse_args(sys.argv[1:])
    run_fcst(
        config_file=args.config_file,
        cycle=args.cycle,
        key_path=args.key_path,
        member=args.member,
    )
