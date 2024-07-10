"""
The run script for UPP
"""

import os
import sys
from copy import deepcopy
from datetime import datetime, timedelta
from pathlib import Path

from uwtools.api import UPP
from uwtools.api.config import get_yaml_config
from uwtools.api.template import render


# Load the YAML config
CONFIG_PATH = os.environ["CONFIG_PATH"]
CYCLE = os.environ["CYCLE"]
LEAD = timedelta(hours=int(os.environ["LEAD"]))
KEY_PATH = os.environ["KEY_PATH"]
os.environ["MEM"] = os.environ.get("MEM", "000")

cycle = datetime.fromisoformat(CYCLE)

# Extract driver config from experiment config
upp_driver = UPP(config=CONFIG_PATH, cycle=cycle, leadtime=LEAD, key_path=[KEY_PATH])
run_dir = upp_driver._config['run_dir']

print(f"Will run in {run_dir}")

# Run upp
upp_driver.run()

if not (run_dir / "runscript.upp.done").is_file():
    print("Error occurred running UPP. Please see component error logs.")
    sys.exit(1)

# Deliver output data
expt_config = uwconfig.get_yaml_config(CONFIG_PATH)
upp_config = expt_config[KEY_PATH]


post_output = run_dir.parent()
output_file_labels = upp_config["output_file_labels"]
for label in output_file_labels:
    upp_config_cp = deepcopy(upp_config)
    upp_config_cp.dereference(context={"cycle": cycle, "leadtime": LEAD,
        fid=fid,
        **expt_config})
    desired_output_fn = upp_cp_config["desired_output_name"]
    upp_output_fn = Path(f"{fid.upper()}.GrbF{int(LEAD.total_seconds() // 3600):03d}")
    upp_output_fn.symlink_to(post_output / desired_output_fn)
