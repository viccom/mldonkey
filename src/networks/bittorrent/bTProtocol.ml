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

  (*

1. Download the .torrent file
*****************************
 {
 "announce" = "http://sucs.org:6969/announce";
 "info" =  {
    "files" =  [
    {
    "length" =  682164224;
    "path" =  [ "Mandrake91-cd1-inst.i586.iso";  ]
    }
    ;
     {
     "length" =  681279488;
     "path" =  [
     "Mandrake91-cd2-ext.i586.iso";
      ]
      ;
       }
       ;
        {
        "length" =  681574400;
        "path" =  [
        "Mandrake91-cd3-i18n.i586.iso";
         ]
         ;
          }
          ;
           ]
           ;
           "name" = "mandrake9.1";
           "piece length" =  262144;
           "pieces" =  "[EAd\155�g۠���f\134ʫ\025\016�͵,1U\150�
\132\147�\n%�\\�,\012�C\008G��d!��uL!\134�\016\152&\017�\008��d\029�3\031�\134
#��\025\137�=�.�\019��\138�.�\151O\137��,��&\019�ۢç\156.�\150<E��\153\018\145\
149d\147[+J=�\155l\139�\028�dV�\000-\017�Ť\013\154�>A��5�It\007\020������\014O�
�1\152U�\026K\021^���5Ϳ��\026\149\131q\024\015�]���\027&\148\\�-�\028WM�5...";
 }
 ;
  }

2. Extract BitTorrent information needed:
*****************************************
  
Metainfo files are bencoded dictionaries with the following keys -

'announce'
    The url of the tracker.

'info'
    This maps to a dictionary, with keys described below.

    The 'name' key maps to a string which is the suggested name to save
    the file (or directory) as. It is purely advisory.

    'piece length' maps to the number of bytes in each piece the file is
    split into. For the purposes of transfer, files are split into
    fixed-size pieces which are all the same length except for possibly
    the last one which may be truncated. Piece length is almost always a
    power of two, most commonly 2^20 .

    'pieces' maps to a string whose length is a multiple of 20. It is to
    be subdivided into strings of length 20, each of which is the sha1
    hash of the piece at the corresponding index.

    There is also a key 'length' or a key 'files', but not both or
    neither. If 'length' is present then the download represents a
    single file, otherwise it represents a set of files which go in a
    directory structure.

    In the single file case, 'length' maps to the length of the file in
    bytes.

    For the purposes of the other keys, the multi-file case is treated
    as only having a single file by concatenating the files in the order
    they appear in the files list. The files list is the value 'files'
    maps to, and is a list of dictionaries containing the following keys -

'length'
The length of the file, in bytes. 'path'
    A list of strings corresponding to subdirectory names, the last of
which is the actual file name (a zero length list is an error case).

In the single file case, the 'name' key is the name of a file, in the
muliple file case, it's the name of a directory.


3. Contact the tracker regularly to update file information
***********************************************************
  
Tracker GET requests have the following keys by HTTP:

'info_hash'
    The 20 byte sha1 hash of the bencoded form of the 'info' value from
    the metainfo file. Note that this is a substring of the metainfo
    file. This value will almost certainly have to be escaped.

'peer_id'
    A string of length 20 which this downloader uses as its id. Each
    downloader generates its own id at random at the start of a new
    download. This value will also almost certainly have to be escaped.

'ip'
    An optional parameter giving the ip (or dns name) which this peer is
    at. Generally used for the origin if it's on the same machine as the
    tracker.

'port'
    The port number this peer is listening on. Common behavior is for a
    downloader to try to listen on port 6881 and if that port is taken
    try 6882, then 6883, etc. and give up after 6889.

'uploaded'
    The total amount uploaded so far, encoded in base ten ascii.

'downloaded'
    The total amount downloaded so far, encoded in base ten ascii.

'left'
    The number of bytes this peer still has to download, encoded in base
    ten ascii. Note that this can't be computed from downloaded and the
    file length since it might be a resume, and there's a chance that
    some of the downloaded data failed an integrity check and had to be
    re-downloaded.

'event'
    This is an optional key which maps to 'started', 'completed', or
    'stopped' (or '', which is the same as not being present). 
  
---> bencoded replu:
  { 'failure reason' = ... }
or
{
 'interval' = ....; (* before next request to tracker *)
 'peers' =  [ 
   {
    'peer id' = ....;
    'ip' - ....;
    'port' = ....;
   };
   ....
  ] 
}

4. Contact every peer regularly
*******************************

Handshake:

type int = BigEndian.int32
  
--->
string8 (prefixed by length): "BitTorrent protocol" 
int8[8]: reserved(zeros)
int8[20 bytes]: Sha1.string (Bencode.encode file.file_info)
int8[20 bytes]: peer id
  
<---
string8 (prefixed by length): "BitTorrent protocol" 
int8[8]: reserved(zeros)
int8[20 bytes]: Sha1.string (Bencode.encode file.file_info)
int8[20 bytes]: peer id

----> disconnect if sha1 don't match, or if peer id is unexpected

msg: 
        int: len of message (byte+payload) 0 -> keepalive sent every 2 minutes
        byte8: opcode of message
        int8[..]: payload
        
opcodes:        
Connections start out choked and not interested.

No payload:
    * 0 - choke: you have been blocked
    * 1 - unchoke: you have been unblocked
    * 2 - interested: I'm interested in downloading this file now
    * 3 - not interested: I'm not interested in downloading this file now
With bencoded payload:
    * 4 - have
          int : index of new completed chunk          
    * 5 - bitfield: 
          string: a bitfield of bit 1 for downloaded chunks
          byte: bits are inverted 0....7 ---> 7 .... 0      
    * 6 - request
          int: index
          int: begin
          int: length (power of 2, 2 ^ 15)
    * 7 - piece
          int: index
          int: begin
          string: piece
    * 8 - cancel: cancel a requesu
          int: index
          int: begin
          int: length (power of 2, 2 ^ 15)

Chock/unchock every 10 seconds        
*)


open BasicSocket
open CommonTypes
open Printf2
open CommonOptions
open Options
open Md4
open CommonGlobals
open BigEndian
open TcpBufferedSocket
open AnyEndian
open BTTypes
  
type ghandler =
  BTHeader of (gconn -> TcpBufferedSocket.t -> 
  (string * Sha1.t) -> unit)
| Reader of (gconn -> TcpBufferedSocket.t -> unit)

and gconn = {
    mutable gconn_handler : ghandler;
    mutable gconn_refill : (TcpBufferedSocket.t -> unit) list;
    mutable gconn_close_on_write : bool;
  }

  
module TcpMessages = struct
    
    type msg = 
    | Choke
    | Unchoke
    | Interested
    | NotInterested
    | Have of int64
    | BitField of string
    | Request of int * int64 * int64
    | Piece of int * int64 * string * int * int
    | Cancel of int * int64 * int64
    | Ping  
    | PeerID of string
    
    
    let to_string msg =
      match msg with
      | Choke -> "Choke"
      | Unchoke -> "Unchoke"
      | Interested -> "Interested"
      | NotInterested -> "NotInterested"
      | Have n -> Printf.sprintf  "Have %Ld" n
      | BitField s -> Printf.sprintf "BitField %s" (String.escaped s)
      | Request (index, offset, len) -> 
          Printf.sprintf "Request %d %Ld[%Ld]" index offset len
      | Piece (index, offset, s, pos, len) -> 
          Printf.sprintf "Piece %d %Ld[%d]" index offset len
      | Cancel (index, offset, len) -> 
          Printf.sprintf "Cancel %d %Ld[%Ld]" index offset len
      | Ping -> "Ping"
      | PeerID s ->  Printf.sprintf  "PeerID [%s]" (String.escaped s)
    
    let parser opcode m = 
        match opcode with
          0 -> Choke
        | 1 -> Unchoke
        | 2 -> Interested
        | 3 -> NotInterested
        | 4 -> Have (get_uint64_32 m 0)
        | 5 -> BitField m
        | 6 -> Request (get_int m 0, get_uint64_32 m 4, get_uint64_32 m 8)
        | 7 -> Piece (get_int m 0, get_uint64_32 m 4, m, 8, String.length m - 8)
        | 8 -> Cancel (get_int m 0, get_uint64_32 m 4, get_uint64_32 m 8)
        | -1 -> PeerID m
        | _ -> raise Not_found
    
    let buf = Buffer.create 100
    
    let write msg = 
      Buffer.clear buf;
      begin
        buf_int buf 0;
        match msg with
        | Choke -> buf_int8 buf 0
        | Unchoke -> buf_int8 buf 1
        | Interested -> buf_int8 buf 2
        | NotInterested -> buf_int8 buf 3
        | Have i -> buf_int8 buf 4; buf_int64_32 buf i
        | BitField string -> buf_int8 buf 5; Buffer.add_string buf string
        | Request (index, pos, len) ->
            buf_int8 buf 6; 
            buf_int buf index; buf_int64_32 buf pos; buf_int64_32 buf len
        | Piece (num, index, s, pos, len) ->
            buf_int8 buf 7; 
            buf_int buf num;
            buf_int64_32 buf index; 
            Buffer.add_substring buf s pos len
        
        | Cancel _ -> ()
        | PeerID _ -> ()
        | Ping -> ()          
      end;
      let s = Buffer.contents buf in
      str_int s 0 (String.length s - 4);
      s
  end


exception Wait_for_more of string
let bt_handler parse_fun handler c sock =
  try
    let b = TcpBufferedSocket.buf sock in
    if not c.client_received_peer_id then
      begin
        (* we get and parse the peer_id here because it may
           not be sent from trackers that test us for NAT
           (they just wait for our handshake response and
           then drop the connection) *)
        if b.len >= 20 then
          begin
            let payload = String.sub b.buf b.pos 20 in
            let p = parse_fun (-1) payload in
            buf_used b 20;
            c.client_received_peer_id <- true;
            try
                handler sock p;
            with e ->
                lprintf "Exception %s in BTProtocol.parse_fun while handling peer_id\n"
                    (Printexc2.to_string e);
                dump payload;
                buf_used b b.len;
                close sock Closed_by_user
          end
        else raise (Wait_for_more "peer_id");
        (* must break the loop even if there is data, because the socket
           could be closed beneath our feet and then b.buf seems to be zero length
           regardless of what b.len tells (this is a bug somewhere in
           tcpBufferedSocket i think) *)
        raise (Wait_for_more "after_peer_id");
      end;
    while b.len >= 4 do
        let msg_len = get_int b.buf b.pos in
        if msg_len < 0 then
          begin
            let (ip,port) = (TcpBufferedSocket.peer_addr sock) in
            lprintf "BT: Unknown message from %s:%d dropped!! peerid:%b data_len:%i msg_len:%i software: %s\n"
                (Ip.to_string ip) port c.client_received_peer_id b.len msg_len c.client_software;
            dump (String.sub b.buf b.pos (min b.len 30));
            buf_used b b.len;
            close sock Closed_by_user;
          end
        else if msg_len > 20000 then
          (* We NEVER request pieces greater than size 20000, this client is
             trying to waste our bandwidth ? *)
          begin
            let (ip,port) = (TcpBufferedSocket.peer_addr sock) in
            lprintf "btprotocol.bt_handler: closed connection from %s:%d because of too much data!! data_len:%i msg_len:%i software: %s\n"
                (Ip.to_string ip) port b.len msg_len c.client_software;
            dump (String.sub b.buf b.pos (min b.len 30));
            buf_used b b.len;
            close sock Closed_by_user
          end
        else if b.len >= 4 + msg_len then
          begin
            buf_used b 4;
            (* lprintf "Message complete: %d\n" msg_len;  *)
            if msg_len > 0 then 
                let opcode = get_int8 b.buf b.pos in
                let payload = String.sub b.buf (b.pos+1) (msg_len-1) in
                buf_used b msg_len;
                (* lprintf "Opcode %d\n" opcode; *)
                try
                    (* We use opcodes < 0 internaly and
                       they don't occur in the spec
                       *)
                    if opcode < 0 then raise Not_found;
                    let p = parse_fun opcode payload in
                    (* lprintf "Parsed, calling handler\n"; *)
                    handler sock p
                with e ->
                    lprintf "Exception %s in BTProtocol.parse_fun while handling message with opcode: %d\n"
                      (Printexc2.to_string e) opcode;
                    dump payload;
            else
                (*received a ping*)
                set_lifetime sock 130.
          end
        else raise (Wait_for_more "message")
    done;
    if b.len != 0 then raise (Wait_for_more "loop")
  with
    | Wait_for_more s ->
        if closed sock && s <> "after_peer_id" then
            lprintf "bt_handler: Socket was closed while waiting for more data in %s\n" s
    | e ->
        lprintf "Exception %s in bt_handler\n"
          (Printexc2.to_string e)


let handlers info gconn =
  let rec iter_read sock nread =
    (* lprintf "iter_read %d\n" nread; *)
    let b = TcpBufferedSocket.buf sock in
    if b.len > 0 then
      match gconn.gconn_handler with
      | BTHeader h ->
	  (* dump (String.sub b.buf b.pos (min b.len 100)); *)
          let slen = get_int8 b.buf b.pos in
          if slen + 29 <= b.len then
            begin
              (* get proto and file_id from handshake,
                 peer_id is not fetched here because
                 it might be late or not present
                 *)
              let proto = String.sub b.buf (b.pos+1) slen in
              let file_id = Sha1.direct_of_string
                (String.sub b.buf (b.pos+9+slen) 20) in
              let proto,pos = get_string8 b.buf b.pos in
              buf_used b (slen+29);
              h gconn sock (proto, file_id);
	    end
          else if (TcpBufferedSocket.closed sock) then
              let (ip,port) = (TcpBufferedSocket.peer_addr sock) in
              lprintf "bt-handshake: closed sock from %s:%d  b.len:%i slen:%i\n"
                (Ip.to_string ip) port b.len slen;

      | Reader h -> 
          h gconn sock
  in
  iter_read
  
let set_bt_sock sock info ghandler = 
  let gconn = {
      gconn_handler = ghandler;
      gconn_refill = [];
      gconn_close_on_write = false;
    } in
  TcpBufferedSocket.set_reader sock (handlers info gconn);
  TcpBufferedSocket.set_refill sock (fun sock ->
      match gconn.gconn_refill with
        [] -> ()
      | refill :: _ -> refill sock
  );
  TcpBufferedSocket.set_handler sock TcpBufferedSocket.WRITE_DONE (
    fun sock ->
      match gconn.gconn_refill with
        [] -> ()
      | _ :: tail -> 
          gconn.gconn_refill <- tail;
          match tail with
            [] -> 
              if gconn.gconn_close_on_write then 
                set_lifetime sock 30.
(*                TcpBufferedSocket.close sock "write done" *)
          | refill :: _ -> refill sock)
              
      
  
(*  
No payload:
    * 0 - choke: you have been blocked
    * 1 - unchoke: you have been unblocked
    * 2 - interested: I'm interested in downloading this file now
    * 3 - not interested: I'm not interested in downloading this file now
With bencoded payload:
    * 4 - have
          int : index of new completed chunk          
    * 5 - bitfield: 
          string: a bitfield of bit 1 for downloaded chunks
          byte: bits are inverted 0....7 ---> 7 .... 0      
    * 6 - request
          int: index
          int: begin
          int: length (power of 2, 2 ^ 15)
    * 7 - piece
          int: index
          int: begin
          string: piece
    * 8 - cancel: cancel a requesu
          int: index
          int: begin
          int: length (power of 2, 2 ^ 15)
*)

let send_client client_sock msg =
    do_if_connected  client_sock (fun sock ->
      try
        let s = TcpMessages.write msg in
        if !verbose_msg_clients then begin
            lprintf "send message: %s\n" (TcpMessages.to_string msg);
          end;
(*        dump s; *)
        write_string sock s
  with e ->
      lprintf "CLIENT : Error %s in send_client\n"
        (Printexc2.to_string e)
)

let zero8 = String.make 8 '\000'
  
let send_init client_uid file_id sock = 
  let buf = Buffer.create 100 in
  buf_string8 buf  "BitTorrent protocol";
  Buffer.add_string buf zero8;
  Buffer.add_string buf (Sha1.direct_to_string file_id);
  Buffer.add_string buf (Sha1.direct_to_string client_uid);
  let s = Buffer.contents buf in
  write_string sock s
  
