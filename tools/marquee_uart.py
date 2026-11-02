"""Send one v2.8 marquee command, wait for its frame-commit ACK, never retry."""
import argparse,time,sys

def make_command(action,text=None):
    if action=='text':
        if text is None or not 1<=len(text)<=128:raise ValueError('Text must contain 1..128 characters.')
        if any(not (32<=ord(c)<=95 or 'a'<=c<='z') for c in text):
            raise ValueError('Use ASCII space..underscore or letters a..z; Chinese, ` and {|}~ are unsupported.')
        return ('CMD:TEXT='+text+'\r\n').encode('ascii'),'CMD:TEXT'
    return ('CMD:MARQ='+('1' if action=='on' else '0')+'\r\n').encode('ascii'),'CMD:MARQ='+('1' if action=='on' else '0')

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--port',required=True);p.add_argument('--timeout',type=float,default=3)
    sub=p.add_subparsers(dest='action',required=True);t=sub.add_parser('text');t.add_argument('text');sub.add_parser('on');sub.add_parser('off')
    a=p.parse_args()
    if a.timeout<=0:p.error('--timeout must be positive')
    try:payload,body=make_command(a.action,getattr(a,'text',None))
    except ValueError as e:p.error(str(e))
    try:import serial
    except ImportError:sys.exit('Install pyserial in the Python environment: python -m pip install pyserial')
    try:
        with serial.Serial(port=None,baudrate=115200,bytesize=8,parity='N',stopbits=1,timeout=.1,write_timeout=a.timeout) as link:
            link.dtr=False;link.rts=False;link.port=a.port;link.open();link.reset_input_buffer()
            link.write(payload);link.flush();deadline=time.monotonic()+a.timeout;line=bytearray()
            while time.monotonic()<deadline:
                c=link.read(1)
                if not c:continue
                if c==b'\n':
                    response=line.decode('ascii',errors='replace').rstrip('\r');line.clear()
                    if response=='[ACK] OK: '+body:print(response);return
                    if response=='[ACK] ERR: '+body:sys.exit('Command rejected; previous subtitle setting retained: '+response)
                    # Complete telemetry and unrelated ACK lines are ignored.
                else:
                    line.extend(c)
                    if len(line)>1024:line.clear()
            sys.exit('Timed out waiting for frame-commit ACK; no automatic retry. Check board and connection before resending.')
    except (serial.SerialException,OSError) as e:sys.exit('Serial connection failed: '+str(e))
if __name__=='__main__':main()
