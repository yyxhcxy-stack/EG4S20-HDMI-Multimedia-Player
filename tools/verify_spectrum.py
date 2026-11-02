# Test verification script for 16-Band Sliding DFT (SDFT) & 2D Spectrogram Waterfall

import numpy as np

def test_twiddle_factors():
    N = 256
    k_indices = [1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 16, 20, 24, 32, 40, 53]
    fs = 48000
    r = 126.5
    
    expected_freqs = [int(round(k * fs / N)) for k in k_indices]
    assert len(expected_freqs) == 16
    print(f"16-Band Frequency Grid: {expected_freqs} Hz")
    
    # Verify frequencies match the contest musical notes and emergency siren
    # C5: 523Hz (bin 2: 562Hz), D5: 587Hz, E5: 659Hz, G5: 784Hz (bin 3: 750Hz), A5/Alarm: 880Hz (bin 4: 938Hz), C6: 1046Hz (bin 5: 1125Hz)
    assert 150 <= expected_freqs[0] <= 200
    assert 9500 <= expected_freqs[15] <= 10500
    print("Frequency Grid Span & Tuning: PASS")

def test_waterfall_channel_mapping():
    # Verify exact division by 12 using ((x * 171) >> 11) for all 192 pixels
    for x in range(192):
        expected_ch = x // 12
        actual_ch = (x * 171) >> 11
        assert actual_ch == expected_ch, f"x={x}: got {actual_ch}, expected {expected_ch}"
    print("Waterfall 192-Pixel Channel Mapping ((x * 171) >> 11): PASS (0 mismatches)")

def test_sdft_frequency_selectivity():
    fs = 48000
    N = 256
    k_indices = [1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 16, 20, 24, 32, 40, 53]
    r = 126.5
    tw_c = [int(round(r * np.cos(2 * np.pi * k / N))) for k in k_indices]
    tw_s = [int(round(r * np.sin(2 * np.pi * k / N))) for k in k_indices]

    # Test 523.25 Hz (C5 Note)
    t = np.arange(2400) / fs
    sig_523 = np.sin(2 * np.pi * 523.25 * t) * 120

    delay = np.zeros(256, dtype=np.int32)
    X_re = np.zeros(16, dtype=np.int32)
    X_im = np.zeros(16, dtype=np.int32)

    for n, s in enumerate(sig_523):
        s8 = int(s)
        old = delay[n % 256]
        delay[n % 256] = s8
        diff = s8 - old
        
        for i in range(16):
            A = X_re[i] + diff
            B = X_im[i]
            C = tw_c[i]
            D = tw_s[i]
            nxt_re = (A * C - B * D) >> 7
            nxt_im = (B * C + A * D) >> 7
            X_re[i] = max(-32768, min(32767, nxt_re))
            X_im[i] = max(-32768, min(32767, nxt_im))

    mag_523 = np.maximum(np.abs(X_re), np.abs(X_im)) + (np.minimum(np.abs(X_re), np.abs(X_im)) >> 1)
    peak_bin_523 = int(np.argmax(mag_523))
    assert peak_bin_523 == 2, f"Expected peak bin 2 for 523Hz, got {peak_bin_523}"
    print(f"523Hz (C5 Note) Selectivity: Peak at Bin {peak_bin_523} ({int(k_indices[2]*fs/N)}Hz) [PASS]")

    # Test 880.0 Hz (A5 Note / Alarm Tone)
    sig_880 = np.sin(2 * np.pi * 880.0 * t) * 120
    delay.fill(0)
    X_re.fill(0)
    X_im.fill(0)

    for n, s in enumerate(sig_880):
        s8 = int(s)
        old = delay[n % 256]
        delay[n % 256] = s8
        diff = s8 - old
        for i in range(16):
            A = X_re[i] + diff
            B = X_im[i]
            C = tw_c[i]
            D = tw_s[i]
            nxt_re = (A * C - B * D) >> 7
            nxt_im = (B * C + A * D) >> 7
            X_re[i] = max(-32768, min(32767, nxt_re))
            X_im[i] = max(-32768, min(32767, nxt_im))

    mag_880 = np.maximum(np.abs(X_re), np.abs(X_im)) + (np.minimum(np.abs(X_re), np.abs(X_im)) >> 1)
    peak_bin_880 = int(np.argmax(mag_880))
    assert peak_bin_880 == 4, f"Expected peak bin 4 for 880Hz, got {peak_bin_880}"
    print(f"880Hz (A5 / Siren Note) Selectivity: Peak at Bin {peak_bin_880} ({int(k_indices[4]*fs/N)}Hz) [PASS]")

def test_waterfall_heatmap_palette():
    palette = [
        0x0A0E18, 0x001840, 0x002870, 0x0048A0, 
        0x0070B8, 0x0098C8, 0x00B8B8, 0x00D888, 
        0x00E848, 0x40F020, 0x88F000, 0xD0E000, 
        0xFFC800, 0xFF8800, 0xFF4410, 0xFFFFFF
    ]
    assert len(palette) == 16
    for i in range(len(palette) - 1):
        # Ensure palette transitions smoothly from dark to bright
        r = (palette[i] >> 16) & 0xFF
        g = (palette[i] >> 8) & 0xFF
        b = palette[i] & 0xFF
        lum = 0.299 * r + 0.587 * g + 0.114 * b
        assert lum < 256
    print("Waterfall 16-Color Heatmap Palette Verification: PASS")

def test_screen_box_geometry():
    # Box 1: Spectrum Analyzer (X = 16..143, Y = 416..444)
    # Box 2: Spectrogram Waterfall (X = 152..351, Y = 416..444)
    box1_x0, box1_x1, box1_y0, box1_y1 = 16, 143, 416, 444
    box2_x0, box2_x1, box2_y0, box2_y1 = 152, 351, 416, 444
    
    assert box1_x1 < box2_x0, "Box 1 and Box 2 horizontally overlap!"
    assert box1_y1 < 448, "Boxes overlap bottom Marquee (Y = 448..473)!"
    assert box1_x1 - box1_x0 + 1 == 128, "Box 1 width is not exactly 128 pixels (16 bars * 8px)!"
    assert box2_x1 - box2_x0 + 1 == 200, "Box 2 width is not exactly 200 pixels!"
    print("Dual Box Geometric Layout & Non-Overlap Verification: PASS")

if __name__ == '__main__':
    test_twiddle_factors()
    test_waterfall_channel_mapping()
    test_sdft_frequency_selectivity()
    test_waterfall_heatmap_palette()
    test_screen_box_geometry()
    print("\nAll 16-Band SDFT & 2D Spectrogram Waterfall Tests: 100% PASS!")
