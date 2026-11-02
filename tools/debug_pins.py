# -*- coding: utf-8 -*-
import pypdf, re

def check():
    r_fpga = pypdf.PdfReader('C:/fpga/HX4S20_Contest_202606/3_原理图/开发板原理图/2_FPGA.pdf')
    txt_fpga = r_fpga.pages[0].extract_text()
    
    # In 2_FPGA.pdf, find lines with K15, J16, H15, H16, K16, M16
    targets = ['K15', 'J16', 'H15', 'H16', 'K16', 'M16', 'M11', 'L12', 'P14', 'K11', 'J11', 'L14']
    for t in targets:
        pos = txt_fpga.find(t)
        if pos != -1:
            print(f"FPGA pin {t}: {txt_fpga[max(0, pos-20):pos+40].replace(chr(10), ' ')}")

    r_gpio = pypdf.PdfReader('C:/fpga/HX4S20_Contest_202606/3_原理图/开发板原理图/4_GPIO.pdf')
    txt_gpio = r_gpio.pages[0].extract_text()
    
    # Match RN (resistor network) connections:
    # e.g. PIRN... NLGPIOA...
    for line in txt_gpio.splitlines():
        if 'NLGPIOA' in line or 'PIJ10' in line:
            print("GPIO line:", line)

if __name__ == '__main__':
    check()
