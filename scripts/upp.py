"""
The run script for UPP
"""

import datetime as dt
import os
import re
import sys
from argparse import ArgumentParser
from copy import deepcopy
from pathlib import Path

from uwtools.api.file import link as uwlink
from uwtools.api.upp import UPP
from uwtools.api.config import get_yaml_config


def _timedelta_from_str(tds: str) -> dt.timedelta:
    """
    Return a timedelta parsed from a leadtime string.

    :param tds: The timedelta string to parse.
    """
    if matches := re.match(r"(\d+)(:(\d+))?(:(\d+))?", tds):
        h, m, s = [int(matches.groups()[n] or 0) for n in (0, 2, 4)]
        return dt.timedelta(hours=h, minutes=m, seconds=s)
    msg = f"Specify leadtime as {tds}"
    print(msg, file=sys.stderr)
    sys.exit(1)


parser = ArgumentParser(
    description="Script that runs UPP via uwtools API",
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
    "--leadtime",
    help="The leadtime as hours[:minutes[:seconds]]",
    required=True,
    type=_timedelta_from_str,
)
parser.add_argument(
    "--key-path",
    help="Dot-separated path of keys leading through the config to the driver's YAML block",
    metavar="KEY[.KEY...]",
    required=True,
)
parser.add_argument(
    "--member",
    default="000",
    help="The 3-digit ensemble member number.",
)
args = parser.parse_args()

os.environ["member"] = args.member

# Extract driver config from experiment config
upp_driver = UPP(
    config=args.config_file,
    cycle=args.cycle,
    leadtime=args.leadtime,
    key_path=[args.key_path],
)
rundir = Path(upp_driver.config["rundir"])
print(f"Will run in {rundir}")
# Run upp
upp_driver.run()

if not (rundir / "runscript.upp.done").is_file():
    print("Error occurred running UPP. Please see component error logs.")
    sys.exit(1)

# Deliver output data
expt_config = get_yaml_config(args.config_file)
upp_config = expt_config[args.key_path]

links = {}
for label in upp_config["output_file_labels"]:
    # deepcopy here because desired_output_name is parameterized within the loop
    expt_config_cp = get_yaml_config(deepcopy(expt_config.data))
    expt_config_cp.dereference(
        context={
            "cycle": args.cycle,
            "leadtime": args.leadtime,
            "file_label": label,
            **expt_config_cp,
        }
    )
    upp_block = expt_config_cp[args.key_path]
    desired_output_fn = upp_block["desired_output_name"]
    upp_output_fn = rundir / f"{label.upper()}.GrbF{int(args.leadtime.total_seconds() // 3600):02d}"
    links[desired_output_fn] = str(upp_output_fn)

uwlink(target_dir=rundir.parent, config=links)
