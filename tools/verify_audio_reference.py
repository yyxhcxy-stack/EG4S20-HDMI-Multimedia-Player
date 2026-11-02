"""Compare actual CXXRTL dumps with an independent Python DFT and floating model."""
from pathlib import Path
from audio_reference import dft, float_dft

def verify():
    rows=iter((Path(__file__).resolve().parents[1]/"output/verification/dft_reference_vectors.txt").read_text().splitlines())
    worst=0.0
    for block in range(22):
        samples=list(map(int,next(rows).split()))
        exact=dft(samples); floating=float_dft(samples)
        for k,(re,im,amp) in enumerate(exact):
            assert tuple(map(int,next(rows).split()))==(re,im,amp),(block,k)
            worst=max(worst,abs(re/2**22-floating[k].real),abs(im/2**22-floating[k].imag))
    assert worst<=8,worst
    return f"Python independent reference: 22 RTL windows exact, worst complex error {worst:.6f} LSB"
if __name__=="__main__": print(verify())
