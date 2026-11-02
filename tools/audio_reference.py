"""Independent v2.6 arithmetic specification; no RTL tables are imported."""
import math

BINS = (1,2,3,4,5,6,7,8,10,12,16,20,24,32,40,53)
def coefficient(phase):
    return int(math.floor(32767 * math.cos(2 * math.pi * phase / 256) + .5))
def dft(samples):
    assert len(samples) == 256
    result=[]
    for k in BINS:
        re=sum(x*coefficient((n*k)&255) for n,x in enumerate(samples))
        im=-sum(x*coefficient((n*k-64)&255) for n,x in enumerate(samples))
        a,b=sorted((abs(re),abs(im)),reverse=True)
        result.append((re,im,min(65535,(a+(b>>1)+(1<<21))>>22)))
    return result
def float_dft(samples):
    return [sum(x*complex(math.cos(-2*math.pi*k*n/256),math.sin(-2*math.pi*k*n/256)) for n,x in enumerate(samples))*2/256 for k in BINS]
def voice_interpolate(a,b,s):
    return a + (s*(b-a)+3)//6
def volume(pcm,gain):
    return max(-8388608,min(8388607,(pcm*gain+128)//256))
