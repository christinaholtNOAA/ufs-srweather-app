"""
The run script for UPP
"""

import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

from uwtools.api import config as uwconfig
from uwtools.api import UPP


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

# Rename/move output data

GrbF06.PLEV


