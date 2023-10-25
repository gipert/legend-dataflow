"""
This script checks that the blinding for a particular channel is still valid, 
it does this by taking the calibration curve stored in the overrides, applying it 
to the daqenergy, running a peak search over the calibrated energy and checking that
there are peaks within 5keV of the 583 and 2614 peaks. If the detector is in ac mode
then it will skip the check.
"""

import argparse
import logging
import os, json
import pathlib
from legendmeta.catalog import Props
from legendmeta import LegendMetadata
import numpy as np
import numexpr as ne
import lgdo.lh5_store as lh5
from pygama.pargen.energy_cal import get_i_local_maxima
from pygama.math.histogram import get_hist
import matplotlib.pyplot as plt
import matplotlib as mpl 
mpl.use("Agg")

argparser = argparse.ArgumentParser()
argparser.add_argument("--files", help="files", nargs="*", type=str)
argparser.add_argument("--output", help="output file", type=str)
argparser.add_argument("--blind_curve", help="blinding curves file", type=str)
argparser.add_argument("--datatype", help="Datatype", type=str, required=True)
argparser.add_argument("--timestamp", help="Timestamp", type=str, required=True)
argparser.add_argument("--configs", help="config file", type=str)
argparser.add_argument("--channel", help="channel", type=str)
argparser.add_argument("--log", help="log file", type=str)
args = argparser.parse_args()

os.makedirs(os.path.dirname(args.log), exist_ok=True)
logging.basicConfig(level=logging.INFO, filename=args.log, filemode="w")
logging.getLogger("numba").setLevel(logging.INFO)
logging.getLogger("parse").setLevel(logging.INFO)
logging.getLogger("lgdo").setLevel(logging.INFO)
logging.getLogger("h5py").setLevel(logging.INFO)
logging.getLogger("matplotlib").setLevel(logging.INFO)
log = logging.getLogger(__name__)

# get the usability status for this channel
chmap = LegendMetadata(args.timestamp).channelmap(args.timestamp).map("daq.rawid")
det_status = chmap[int(args.channel[2:])]["analysis"]["usability"]

#read in calibration curve for this channel
blind_curve = Props.read_from(args.blind_curve)[args.channel]

# load in the data
daqenergy = lh5.load_nda(sorted(args.files), ["daqenergy"],f"{args.channel}/raw")["daqenergy"]

# calibrate daq energy using pre existing curve
daqenergy_cal = ne.evaluate(
                blind_curve["daqenergy_cal"]["expression"],
                local_dict=dict(daqenergy=daqenergy, **blind_curve["daqenergy_cal"]["parameters"])
            )

# bin with 1 keV bins and get maxs
hist, bins, var = get_hist(daqenergy_cal, np.arange(0,3000,1))
maxs = get_i_local_maxima(hist, delta =5)
log.info(f"peaks found at : {maxs}")

# plot the energy spectrum to check calibration
plt.figure()
plt.step((bins[1:]+bins[:-1])/2, hist, where="mid")
plt.close()


# check for peaks within +- 5keV of  2614 and 583 to ensure blinding still valid and if so create file else raise error
# if detector is in ac mode it will always pass this check
if np.any(np.abs(maxs-2614)<5) and np.any(np.abs(maxs-583)<5) or det_status=="ac":
    pathlib.Path(os.path.dirname(args.output)).mkdir(parents=True, exist_ok=True)
    with open(args.output,"w") as f:
        json.dump({}, f)
else:
    raise RuntimeError("peaks not found in daqenergy")