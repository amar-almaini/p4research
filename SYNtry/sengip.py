
from scapy.all import *

import networkx as nx
import time
import sys

fwd_pkt1 = Ether() / IP(dst = '192.168.0.10')/TCP(sport=5793,dport=80,flags = "S")/Raw("S")

for x in range(1):
    temppkt  = Ether() / IP(dst = '192.168.0.10')/TCP(sport=5793,dport=80,flags = "S")/Raw("S"+str(x))
    sendp(temppkt, iface = "eth0")

time.sleep(2)

for y in range(1):
    temppkt = Ether() / IP(dst = '192.168.0.10')/TCP(sport=5793,dport=80,flags = "A")/Raw("A"+str(x))
    print(temppkt)
    sendp(temppkt, iface = "eth0")

