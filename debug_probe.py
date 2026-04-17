import os, glob
for f in sorted(glob.glob("/proc/asound/card*/pcm*/sub*/hw_params")):
    print(f"=== {f} ===")
    try:
        print(open(f).read())
    except:
        print("(error reading)")
for f in sorted(glob.glob("/proc/asound/card*/pcm*/sub*/info")):
    print(f"=== {f} ===")
    try:
        print(open(f).read())
    except:
        print("(error reading)")