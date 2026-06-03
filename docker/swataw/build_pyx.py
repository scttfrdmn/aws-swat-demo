# Pre-compile the QSWAT+ Cython extensions in place so pyximport/import finds .so.
import os, sys, numpy, subprocess, sysconfig
qdir = "/root/.SWAT/SWATPlus/Workflow/qswatplus"
pyinc = sysconfig.get_path("include")
npinc = numpy.get_include()
os.chdir(qdir)
for mod in ["polygonizeInC2","polygonizeInC","dataInC","jenks"]:
    subprocess.check_call([sys.executable,"-m","cython","-3",mod+".pyx"])
    so = mod + sysconfig.get_config_var("EXT_SUFFIX")
    subprocess.check_call(["gcc","-shared","-fPIC","-O2",
        "-I"+pyinc,"-I"+npinc, mod+".c","-o",so])
    print("built", so)
