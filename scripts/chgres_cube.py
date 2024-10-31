#!/usr/bin/env python
"""
The run script for chgres_cube
"""

import datetime as dt
import logging
import os
import sys
from argparse import ArgumentParser
from copy import deepcopy
from pathlib import Path

from uwtools.api.chgres_cube import ChgresCube
from uwtools.api.config import get_yaml_config
from uwtools.api.fs import link as uwlink
from uwtools.api.logging import use_uwtools_logger


def _walk_key_path(config, key_path):
    """
    Navigate to the sub-config at the end of the path of given keys.
    """
    keys = []
    pathstr = "<unknown>"
    for key in key_path:
        keys.append(key)
        pathstr = " -> ".join(keys)
        try:
            subconfig = config[key]
        except KeyError:
            logging.error(f"Bad config path: {pathstr}")
            raise
        if not isinstance(subconfig, dict):
            logging.error(f"Value at {pathstr} must be a dictionary")
            sys.exit(1)
        config = subconfig
    return config


def parse_args(argv):
    """
    Parse arguments for the script.
    """
    parser = ArgumentParser(
        description="Script that runs chgres_cube via uwtools API",
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
        help="The cycle in ISO8601 format (e.g. 2024-07-15T18)",
        required=True,
        type=dt.datetime.fromisoformat,
    )
    parser.add_argument(
        "--key-path",
        help="Dot-separated path of keys leading through the config to the driver's YAML block",
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


# pylint: disable-next=too-many-locals, too-many-statements
def run_chgres_cube(config_file, cycle, key_path, member):
    """
    Setup and run the chgres_cube Driver.
    """
    expt_config = get_yaml_config(config_file)

    # The experiment config will have {{ CRES | env }} expressions in it that need to be
    # dereferenced during driver initialization
    cres = expt_config["workflow"]["CRES"]
    os.environ["CRES"] = cres
    os.environ["MEMBER"] = member
    expt_config.dereference(
        context={
            "cycle": cycle,
            **os.environ,
            **expt_config,
        }
    )
    chgres_cube_driver = ChgresCube(
        config=config_file,
        cycle=cycle,
        key_path=key_path,
    )
    rundir = Path(chgres_cube_driver.config["rundir"])
    logging.info(f"Will run in {rundir}")

    chgres_cube_config = _walk_key_path(expt_config, key_path)
    input_type = chgres_cube_config["chgres_cube"]["namelist"]["update_values"][
        "config"
    ].get("input_type")

    varsfilepath = chgres_cube_config["input_files_metadata_path"]
    external_config = get_yaml_config(varsfilepath)
    external_config_fns = external_config["external_model_fns"]
    external_config_fhrs = external_config["external_model_fhrs"]

    # update config for ics task, run and stage data
    if "task_make_ics" in key_path:
        if input_type == "grib2":
            os.environ["fn_grib2"] = external_config_fns[0]
        else:
            os.environ["fn_atm"] = external_config_fns[0]
            os.environ["fn_sfc"] = external_config_fns[1]
        # reinstantiate driver
        expt_config_cp = get_yaml_config(deepcopy(expt_config.data))
        expt_config_cp.dereference(
            context={
                "cycle": cycle,
                **os.environ,
                **expt_config_cp,
            }
        )
        chgres_cube_driver = ChgresCube(
            config=expt_config_cp,
            cycle=cycle,
            key_path=key_path,
        )
        chgres_cube_driver.run()

        # Deliver output data to a common location above the rundir.
        links = {}

        output_dir = os.path.join(rundir.parent, "INPUT")
        os.makedirs(output_dir, exist_ok=True)
        task_get_block = _walk_key_path(expt_config_cp, {"task_get_extrn_ics"})
        task_make_block = _walk_key_path(expt_config_cp, key_path)
        for i, output_fn in enumerate(task_make_block["output_file_labels"]):
            input_fn = task_get_block["output_file_labels"][i]
            links[output_fn] = str(rundir / input_fn)

        uwlink(target_dir=output_dir, config=links)

    #  update config for lbcs task, loop run and stage data
    else:
        num_fhrs = len(external_config_fhrs)

        bcgrp10 = 0
        bcgrpnum10 = 1
        for ii in range(bcgrp10, num_fhrs, bcgrpnum10):
            i = ii + bcgrp10
            if i < num_fhrs:
                print(f"group {bcgrp10} processes member {i}")
                if input_type == "grib2":
                    os.environ["fn_grib2"] = external_config_fns[i]
                else:
                    os.environ["fn_atm"] = external_config_fns[i]

                lbc_spec_fhrs = external_config_fhrs[i]
                lbc_offset_fhrs = expt_config["task_get_extrn_lbcs"]["envvars"][
                    "EXTRN_MDL_LBCS_OFFSET_HRS"
                ]
                fcst_hhh = int(lbc_spec_fhrs) - int(lbc_offset_fhrs)
                os.environ["fcst_hhh_FV3LAM"] = f"{fcst_hhh:03d}"

                # reinstantiate driver
                expt_config_cp = get_yaml_config(deepcopy(expt_config.data))
                expt_config_cp.dereference(
                    context={
                        "cycle": cycle,
                        **os.environ,
                        **expt_config_cp,
                    }
                )
                chgres_cube_driver = ChgresCube(
                    config=expt_config_cp,
                    cycle=cycle,
                    key_path=key_path,
                )
                chgres_cube_driver.run()

                # Deliver output data to a common location above the rundir.
                links = {}

                task_get_block = _walk_key_path(expt_config_cp, {"task_get_extrn_lbcs"})
                task_make_block = _walk_key_path(expt_config_cp, key_path)

                output_dir = os.path.join(rundir.parent, "INPUT")
                os.makedirs(output_dir, exist_ok=True)

                lbc_input_fn = task_get_block["output_file_labels"][0]
                lbc_output_fn = task_make_block["output_file_labels"][0]
                links[lbc_output_fn] = str(rundir / lbc_input_fn)
                uwlink(target_dir=output_dir, config=links)

    # error message
    if not (rundir / "runscript.chgres_cube.done").is_file():
        print("Error occurred running chgres_cube. Please see component error logs.")
        sys.exit(1)


if __name__ == "__main__":

    use_uwtools_logger()

    args = parse_args(sys.argv[1:])
    run_chgres_cube(
        config_file=args.config_file,
        cycle=args.cycle,
        key_path=args.key_path,
        member=args.member,
    )
