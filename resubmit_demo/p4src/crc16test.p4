
header_type ethernet_t {
	fields {
	dstAddr : 48;
	srcAddr : 48;
	etherType : 16;
	}
}

header_type ipv4_t {
	fields {
	version : 4;
	ihl : 4;
	diffserv : 8;
	totalLen : 16;
	identification : 16;
	flags : 3;
	fragOffset : 13;
	ttl : 8;
	protocol : 8;
	hdrChecksum : 16;
	srcAddr : 32;
	dstAddr: 32;
	}
} 
parser start {
	
	set_metadata(meta.in_port, standard_metadata.ingress_port);

	//register_write(temp_write,
	//		   0,
	//		   meta.in_port);
	return  parse_ethernet;
	
}
#define ETHERTYPE_IPV4 0x0800

header ethernet_t ethernet;

parser parse_ethernet {
	extract(ethernet);
	return select(latest.etherType) {
		ETHERTYPE_IPV4 : parse_ipv4;
		default: ingress;
	}
}

header ipv4_t ipv4;

field_list ipv4_checksum_list {
	ipv4.version;
	ipv4.ihl;
	ipv4.diffserv;
	ipv4.totalLen;
	ipv4.identification;
	ipv4.flags;
	ipv4.fragOffset;
	ipv4.ttl;
	ipv4.protocol;
	ipv4.srcAddr;
	ipv4.dstAddr;
}
field_list_calculation ipv4_checksum {
	input {
		ipv4_checksum_list;
	}
	algorithm : csum16;
	output_width : 16;
}

calculated_field ipv4.hdrChecksum  {
	verify ipv4_checksum;
	update ipv4_checksum;
}

#define IP_PROT_TCP 0x06

parser parse_ipv4 {
	extract(ipv4);
	
	set_metadata(meta.ipv4_sa, ipv4.srcAddr);
	set_metadata(meta.ipv4_da, ipv4.dstAddr);
	set_metadata(meta.tcpLength, ipv4.totalLen - 20);	
	return select(ipv4.protocol) {
		IP_PROT_TCP : parse_tcp;
		default: ingress;
	}
	
}

header_type tcp_t {
	fields {
		srcPort : 16;
		dstPort : 16;
		seqNo : 32;
		ackNo : 32;
		dataOffset : 4;
        res : 4;
        flags : 3;
		ack: 1;
		psh: 1;
		rst: 1;
		syn: 1;
		fin: 1;		 
        window : 16;
        checksum : 16;
        urgentPtr : 16;
    }
}


header tcp_t tcp;

parser parse_tcp {
	extract(tcp);
	set_metadata(meta.tcp_sp, tcp.srcPort);
	set_metadata(meta.tcp_dp, tcp.dstPort);
	set_metadata(meta.tcp_ack, tcp.ack);
	set_metadata(meta.tcp_psh, tcp.psh);
	set_metadata(meta.tcp_rst, tcp.rst);
	set_metadata(meta.tcp_syn, tcp.syn);
	set_metadata(meta.tcp_fin, tcp.fin);	
	return ingress;
}
field_list tcp_checksum_list {
        ipv4.srcAddr;
        ipv4.dstAddr;
        8'0;
        ipv4.protocol;
        meta.tcpLength;
        tcp.srcPort;
        tcp.dstPort;
        tcp.seqNo;
        tcp.ackNo;
        tcp.dataOffset;
        tcp.res;
        tcp.flags;
		tcp.ack;
		tcp.psh;
		tcp.rst;
		tcp.syn;
		tcp.fin;		 
        tcp.window;
        tcp.urgentPtr;
        payload;
}

field_list_calculation tcp_checksum {
    input {
        tcp_checksum_list;
    }
    algorithm : csum16;
    output_width : 16;
}

calculated_field tcp.checksum {
    verify tcp_checksum if(valid(tcp));
    update tcp_checksum if(valid(tcp));
}


header_type intrinsic_metadata_t {
	fields {
		mcast_grp:4;
		egress_rid:4;
		mcast_hash:16;
		lf_field_list:32;
			
	}
}

metadata intrinsic_metadata_t intrinsic_metadata;

header_type meta_t {
	fields {
		do_forward : 1;
        ipv4_sa : 32;
        ipv4_da : 32;
        tcp_sp : 16;
        tcp_dp : 16;
        nhop_ipv4 : 32;
        if_ipv4_addr : 32;
        if_mac_addr : 48;
        is_ext_if : 1;
        tcpLength : 16;
        in_port : 8;
	
		reply_type:2;//00 noreply  01 syn/ack  
		tcp_ack:1;
		tcp_psh:1;
		tcp_rst:1;
		tcp_syn:1;
		tcp_fin:1;
		tcp_session_map_index :  13;
		dstip_pktcount_map_index: 13;
								 
		tcp_session_id : 16;
		
		dstip_pktcount:32;	 
	

		tcp_session_is_SYN: 8;// this session has sent a syn to switch
		tcp_session_is_ACK: 8;// this session has sent a ack to switch
		
	}

}

metadata meta_t meta;

field_list l3_hash_fields {

    ipv4.srcAddr;   
	ipv4.dstAddr;
	ipv4.protocol;
	tcp.srcPort;	

	tcp.dstPort;
}

field_list reverse_l3_hash_fields {
	ipv4.dstAddr;
	ipv4.srcAddr;
	ipv4.protocol;
	tcp.dstPort;
	tcp.srcPort;

}
field_list_calculation tcp_session_map_hash {
	input {
		l3_hash_fields;
	}
	algorithm: crc16;
	output_width: 13;
}
field_list_calculation reverse_tcp_session_map_hash {
	input {
		reverse_l3_hash_fields;
	}
	algorithm:crc16;
	output_width:13;
}

register temp_write
{
	width: 32;
	instance_count:300;
}
action _drop()
{
	drop();
}

action write_hash()
{


	modify_field_with_hash_based_offset(meta.tcp_session_map_index,0,
			tcp_session_map_hash,13);


	register_write(
			temp_write,
			1,
			meta.tcp_session_map_index);

}


action write_reverse_hash()
{
	modify_field_with_hash_based_offset(meta.tcp_session_map_index, 0,
					reverse_tcp_session_map_hash,13);
	register_write(
			temp_write,
			2,
			meta.tcp_session_map_index);
}


table write_hash_table
{
	reads{
		meta.in_port:exact;
	}
	actions {
		_drop;
		write_hash;
		write_reverse_hash;
	}
}
control ingress
{
	apply(write_hash_table);
}

control egress
{
}
