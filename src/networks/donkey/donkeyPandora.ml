(* Copyright 2001, 2002 b8_bavard, b8_fee_carabine, INRIA *)
(*
    This file is part of mldonkey.

    mldonkey is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    mldonkey is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with mldonkey; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*)

open Int64ops
open Options
open Queues
open Printf2
open Md4
open BasicSocket
open TcpBufferedSocket

open AnyEndian
open LittleEndian
  
open CommonOptions
open CommonSearch
open CommonServer
open CommonComplexOptions
open CommonFile
open CommonDownloads
open CommonTypes
open CommonGlobals
  
open DonkeyTypes
open DonkeyProtoClient
open DonkeyOptions

type t = UDP | TCP

type cnx = {
    ip1 : string;
    port1 : int;
    ip2 : string;
    port2 : int;
    packets_in : Buffer.t;
    packets_out : Buffer.t;
  }

type client = {
    client_proto : emule_proto;
    mutable client_comp : compressed_parts option;
  }
  
let extendedrequest e = e.emule_extendedrequest
  
let connections = Hashtbl.create 13
let udp_packets = ref []
  
let first_message parse b =
  let pos = ref 0 in
  let len = String.length b in
  if len - !pos >= 5 then
    let opcode = get_uint8 b !pos in
    let msg_len = get_int b (!pos+1) in
    if len - !pos >= 5 + msg_len then
      begin
        let s = String.sub b (!pos+5) msg_len in
        pos := !pos +  msg_len + 5;
        parse opcode s
      end
    else raise Not_found
  else
    raise Not_found

let cut_messages parse b =
  let pos = ref 0 in
  let len = String.length b in
  try
    while len - !pos >= 5 do
      let opcode = get_uint8 b !pos in
      let msg_len = get_int b (!pos+1) in
      if len - !pos >= 5 + msg_len then
        begin
          let s = String.sub b (!pos+5) msg_len in
          pos := !pos +  msg_len + 5;
          parse opcode s
        end
      else raise Not_found
    done
  with Not_found -> ()

let update_emule_proto_from_tags e tags = 
  List.iter (fun tag -> 
      match tag.tag_name with
      | Field_UNKNOWN "compression" ->
          for_int_tag tag (fun i -> 
              e.emule_compression <- i)
      | Field_UNKNOWN "udpver" ->
          for_int_tag tag (fun i -> 
              e.emule_udpver <- i)          
      | Field_UNKNOWN "udpport" -> ()
      | Field_UNKNOWN "sourceexchange" ->
          for_int_tag tag (fun i -> 
              e.emule_sourceexchange <- i)          
      | Field_UNKNOWN "comments" ->
          for_int_tag tag (fun i -> 
              e.emule_comments <- i)          
      | Field_UNKNOWN "extendedrequest" ->
          for_int_tag tag (fun i -> 
              e.emule_extendedrequest <- i)          
      | Field_UNKNOWN "features" ->
          for_int_tag tag (fun i -> 
              e.emule_secident <- i land 0x3)          
      | s -> 
          if !verbose_msg_clients then
            lprintf "Unknown Emule tag: [%s]\n" (string_of_field s)
  ) tags

let client_parse c opcode s =
  let emule = c.client_proto in
  if extendedrequest emule >= 0 then begin
      let module P = DonkeyProtoClient in
      let t = P.parse emule opcode s in
      (match t with
          P.EmuleClientInfoReq info 
        | P.EmuleClientInfoReplyReq info ->
            let tags = info.P.EmuleClientInfo.tags in
            update_emule_proto_from_tags emule tags;
        
        | P.ConnectReq { P.Connect.tags = tags }
        | P.ConnectReplyReq { P.Connect.tags = tags } ->
            
            begin
              try
                let options = find_tag (Field_UNKNOWN "emule_miscoptions1") tags in
                match options with
                  Uint64 v | Fint64 v ->
                    update_emule_proto_from_miscoptions1 emule v
                | _ -> 
                    Printf.printf "CANNOT INTERPRETE EMULE OPTIONS";
                    print_newline ();
              
              with _ -> ()
            end;
        
        | P.UnknownReq (227,_) -> 
            emule.emule_extendedrequest <-  -1
        
        | P.EmuleCompressedPart (md4, statpos, newsize, bloc) ->
            
            let comp = match c.client_comp with
                None ->
                  let comp = {
                      comp_md4 = md4;
                      comp_pos = statpos;
                      comp_total = Int64.to_int newsize;
                      comp_len = 0;
                      comp_blocs = [];
                    } in
                  c.client_comp <- Some comp;
                  comp
              | Some comp -> comp
            in
            comp.comp_blocs <- bloc :: comp.comp_blocs;
            comp.comp_len <- comp.comp_len + String.length bloc;

(*            lprintf "Comp bloc: %d/%d\n" comp.comp_len comp.comp_total; *)
            if comp.comp_len = comp.comp_total then begin
                lprintf "Compressed bloc received !!!!!!\n";
                
                let s = String.create comp.comp_len in
                let rec iter list =
                  match list with
                    [] -> 0
                  | b :: tail ->
                      let pos = iter tail in
                      let len = String.length b in
                      String.blit b 0 s pos len;
                      pos + len
                in
                let pos = iter comp.comp_blocs in
                assert (pos = comp.comp_len);
                if Autoconf.has_zlib then
                  let s = Autoconf.zlib__uncompress_string2 s in
                  lprintf "Decompressed: %d/%d\n" (String.length s) comp.comp_len;
                else
                  lprintf "No Zlib to uncompress packet";
                  
                c.client_comp <- None;
              end else
            if comp.comp_len > comp.comp_total then begin
                lprintf "ERROR: more data than compressed!!!\n";
                c.client_comp <- None;
              end
            
        | _ -> ());
      P.print t; lprintf "\n";
      
      
      let b = Buffer.create 100 in
      let magic = DonkeyProtoClient.write emule b t in
      let ss = Buffer.contents b in
      if ss <> s then begin
          if opcode = 212 then begin
            let tt = P.parse emule 0xc5 ss in
            if t <> tt then begin
                lprintf "======= Parsing/Unparsing differs!!\n";
                P.print tt;
                lprintf "\n---------->\n";
                end 
              
          end else begin
              lprintf "<---------- %d \n" (String.length ss) ;
              dump ss;
              lprintf "=========== %d %d\n" opcode (String.length s);
              dump s;
              lprintf "---------->\n";
            end
        end
    end;
  if extendedrequest emule < 0 then
    let module P = DonkeyProtoServer in
    let t = P.parse opcode s in
    P.print t; print_newline ();
    match t with
      P.UnknownReq _ -> emule.emule_extendedrequest <- 100
    | _ -> ()
        
    
    
let commit () =  

  let oc = open_out "trace.out" in
  output_value oc connections;
  close_out oc

exception ServerConnection
  
let read_trace () =
  let ic = open_in "trace.out" in
  let connections = input_value ic in
  close_in ic;

  mldonkey_emule_proto.emule_sourceexchange <- 5;
  
  Hashtbl.iter (fun _ cnx ->
      try
        
        let emule = { dummy_emule_proto with 
            emule_version = 0;
            emule_extendedrequest = 2; } in        

        let c = {
            client_proto = emule;
            client_comp = None;
          } in
        
        let buffer = Buffer.contents cnx.packets_in in
        (try
            let module D = DonkeyProtoClient in
            let t = first_message 
              (D.parse emule) buffer in
            (match t with
              | D.EmuleClientInfoReplyReq _
              | D.EmuleClientInfoReq _
              | D.ConnectReq _
              | D.ConnectReplyReq _ ->
                  Printf.printf "CLIENT CONNECTION"; print_newline ();
                  
              | D.UnknownReq _ -> 
                  D.print t; print_newline ();
                  raise ServerConnection
                  
              | _ -> 
                  D.print t; print_newline ();
                  Printf.printf "COULD NOT RECOGNIZE CONNECTION";
                  print_newline ()
            );
          with 
          | ServerConnection ->
              Printf.printf "PROBABLY A SERVER CONNECTION"; print_newline ();
          | Not_found ->
              Printf.printf "EMPTY CONNECTION (%d)" (String.length buffer); 
              print_newline ();
        );
        
        lprintf "CONNECTION %s:%d --> %s:%d" 
          cnx.ip1 cnx.port1 cnx.ip2 cnx.port2; print_newline ();
        Printf.printf "  INCOMING:"; print_newline ();
        cut_messages (client_parse c) buffer;
        Printf.printf "  OUTGOING:"; print_newline ();
        cut_messages (client_parse c)
        (Buffer.contents cnx.packets_out);
        
      with           
      | e ->
          lprintf "Exception %s\n" (Printexc2.to_string e)
  ) connections

let new_packet (kind:t) (number:int) ip1 port1 ip2 port2 data = 
  match kind with
    UDP -> 
      begin
        try
          udp_packets := (ip1,port1,ip2,port2,data) :: !udp_packets;
(*              lprintf "New packet:\n%s\n" (String.escaped data);           *)
          ()
        with e ->
(*                lprintf "Could not parse UDP packet:\n"; *)
            ()
      end
  | TCP -> 
      let out_packet = (ip1, port1, ip2, port2) in
      let in_packet = (ip2, port2, ip1, port1) in
      
      try
        let cnx =  Hashtbl.find connections out_packet in
        Buffer.add_string cnx.packets_out data; 
        ()
      with _ ->
          try
            let cnx =  Hashtbl.find connections in_packet in
            Buffer.add_string cnx.packets_in data 
          with _ ->
              let cnx = {
                  ip1 = ip1;
                  port1 = port1;
                  ip2 = ip2;
                  port2 = port2;
                  packets_out = Buffer.create 100;
                  packets_in = Buffer.create 100;
                } in
              Hashtbl.add connections out_packet cnx;
              Buffer.add_string cnx.packets_out data
              
              
              
              