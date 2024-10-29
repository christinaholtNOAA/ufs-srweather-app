#!/usr/bin/env python
"""
The run script for sfc_climo_gen 
"""

import glob
import os
import sys
from argparse import ArgumentParser
from pathlib import Path

from uwtools.api.config import get_yaml_config
from uwtools.api.fs import link as uwlink
from uwtools.api.logging import use_uwtools_logger
from uwtools.api.sfc_climo_gen import SfcClimoGen 


def _link_files(dest_dir, files, cres):
    """
    Link a given list of files to the destination directory updating the file names.
    """
    for fpath in files:
        path = Path(fpath)
        fn = Path(fpath).name
    
        if "halo" in fn:
            fn = f"{cres}.{(fn.replace('halo', 'halo4'))}"
            no_halo_fn = fn.replace("halo4.", "")
            for link in (fn, no_halo_fn):
                link = Path(link)
                if (linkname := dest_dir / link.name).is_symlink():
                    linkname.unlink()
                linkname.symlink_to(path)
    
        else:
            basename = path.stem
            halo0_fn = f"{cres}.{basename}.halo0.nc"
            tile1_fn = halo0_fn.replace("tile7.halo0", "tile1")
            for link in (halo0_fn, tile1_fn):
                link = Path(link)
                if (linkname := dest_dir / link.name).is_symlink():
                    linkname.unlink()
                linkname.symlink_to(path)

def parse_args(argv):
    parser = ArgumentParser(
        description="Script that runs sfc_climo_gen via uwtools API.",
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
        help="Dot-separated path of keys leading through the config to the driver's YAML block.",
        metavar="KEY[.KEY...]",
        required=True,
        type=lambda s: s.split("."),
    )
    
    return parser.parse_args(argv)


def make_sfc_climo(config_file, key_path):
    """
    Run the sfc_climo_gen driver.
    """
    expt_config = get_yaml_config(config_file)
    
    # The experiment config will have {{ CRES | env }} expressions in it that need to be
    # dereferenced during driver initialization
    cres = expt_config["workflow"]["CRES"]
    os.environ["CRES"] = cres 
    expt_config.dereference(
        context={
            **os.environ,
            **expt_config,
        }
    )
    sfc_climo_gen_driver = SfcClimoGen(
        config=config_file,
        key_path=key_path,
    ) 
    rundir = Path(sfc_climo_gen_driver.config["rundir"])
    print(f"Will run sfc_climo_gen in {rundir}")
    sfc_climo_gen_driver.run()
    
    if not (rundir / "runscript.sfc_climo_gen.done").is_file():
        print("Error occurred running sfc_climo_gen. Please see component error logs.")
        sys.exit(1)
    
    
    # Destination of important files from this process
    fix_lam_path = Path(expt_config["workflow"]["FIXlam"])
    # Link sfc_climo_gen output data to fix directory
    _link_files(
        dest_dir=fix_lam_path,
        files=glob.glob(str(rundir / f"*.nc")),
        cres=cres,
    )
    
    # Mark the successful completion of the script on disk
    Path(rundir / "make_sfc_climo_task_complete.txt").touch()


if __name__ == "__main__":

    use_uwtools_logger()

    args = parse_args(sys.argv[1:])
    make_sfc_climo(
        config_file=args.config_file,
        key_path=args.key_path,
    )
