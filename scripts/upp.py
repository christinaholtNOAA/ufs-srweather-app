"""
The run script for UPP
"""

import os
import sys
from copy import deepcopy
from datetime import datetime, timedelta
from pathlib import Path

from uwtools.api.upp import UPP
from uwtools.api.config import get_yaml_config


# Load the YAML config
CONFIG_PATH = os.environ["CONFIG_PATH"]
CYCLE = os.environ["CYCLE"]
LEAD = timedelta(hours=int(os.environ["LEAD"]))
KEY_PATH = os.environ["KEY_PATH"]
os.environ["MEM"] = os.environ.get("MEM", "000")

cycle = datetime.fromisoformat(CYCLE)

# Extract driver config from experiment config
upp_driver = UPP(config=CONFIG_PATH, cycle=cycle, leadtime=LEAD, key_path=[KEY_PATH])
rundir = upp_driver.config["rundir"]

print(f"Will run in {rundir}")

# Run upp
upp_driver.run()

if not (rundir / "runscript.upp.done").is_file():
    print("Error occurred running UPP. Please see component error logs.")
    sys.exit(1)

# Deliver output data
expt_config = get_yaml_config(CONFIG_PATH)
upp_config = expt_config[KEY_PATH]


post_output = rundir.parent()
output_file_labels = upp_config["output_file_labels"]
for label in output_file_labels:
    upp_config_cp = deepcopy(upp_config)
    upp_config_cp.dereference(
        context={"cycle": cycle, "leadtime": LEAD, "file_label": label, **expt_config}
    )
    desired_output_fn = upp_config_cp["desired_output_name"]
    upp_output_fn = Path(f"{label.upper()}.GrbF{int(LEAD.total_seconds() // 3600):03d}")
    upp_output_fn.symlink_to(post_output / desired_output_fn)
