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

open Printf2
open Options

open BasicSocket
open TcpBufferedSocket
  
open CommonDownloads
open CommonNetwork
open CommonInteractive
open CommonClient
open CommonFile
open CommonComplexOptions
open CommonTypes
open CommonOptions
open CommonGlobals
  
open DonkeyMftp
open DonkeyProtoCom
open DonkeyServers
open DonkeyComplexOptions
open DonkeyOneFile
open DonkeyFiles
open DonkeyTypes  
open DonkeyGlobals
open DonkeyClient
open DonkeyThieves
open DonkeyOptions


let _ =
  network.op_network_is_enabled <- (fun _ -> !!enable_donkey);
  option_hook enable_donkey (fun _ ->
      if !CommonOptions.start_running_plugins then
        if !!enable_donkey then network_enable network
        else network_disable network);
  network.network_config_file <- [
    donkey_ini]

let hourly_timer timer =
  DonkeyClient.clean_groups ();
  DonkeyClient.clean_requests ();
  Hashtbl.clear udp_servers_replies;
  DonkeyThieves.clean_thieves ();
  DonkeyNeighbours.recover_downloads !current_files
    
let quarter_timer timer =
  clean_join_queue_tables ()

let fivemin_timer timer =
  DonkeyShare.send_new_shared ();
  DonkeyChunks.duplicate_chunks ();
(*  DonkeySources.clean_sources (); *)
  clients_root := []

let second_timer timer =
  (try
      DonkeySources.connect_sources connection_manager;
    with e ->
        if !verbose_sources > 2 then 
          lprintf "Exception %s while checking sources\n" 
            (Printexc2.to_string e)
  )

let halfmin_timer timer =
  DonkeySources.clean_sources ();
  DonkeyServers.update_master_servers ()
(*  DonkeyIndexer.add_to_local_index_timer () *)


let local_login () =
  if !!login = "" then !!global_login else !!login
  
let is_enabled = ref false
  
let disable enabler () =
  if !enabler then begin
      is_enabled := false;
      enabler := false;
      if !!enable_donkey then enable_donkey =:= false;
      Hashtbl2.safe_iter (fun s -> disconnect_server s Closed_by_user)
      servers_by_key;
      H.iter (fun c -> DonkeyClient.disconnect_client c Closed_by_user) 
      clients_by_kind;
      (match !listen_sock with None -> ()
        | Some sock -> 
            listen_sock := None;
            TcpServerSocket.close sock Closed_by_user);
      (match !reversed_sock with None -> ()
        | Some sock -> 
            reversed_sock := None;
            TcpServerSocket.close sock Closed_by_user);
      (match !udp_sock with None -> ()
        | Some sock -> 
            udp_sock := None;
            UdpSocket.close sock Closed_by_user);
      servers_list := [];
      if !!enable_donkey then enable_donkey =:= false;
      DonkeyProtoOvernet.Overnet.disable ();
      DonkeyProtoKademlia.Kademlia.disable ()
    end

let reset_tags () =
  let module D = DonkeyProtoClient in
  let m = D.mldonkey_emule_proto in
  let emule_miscoptions1 = D.emule_miscoptions1 m in
  client_to_client_tags :=
  [
    string_tag (Field_UNKNOWN "name") (local_login ());
    int_tag (Field_UNKNOWN "version") protocol_version;
    int_tag (Field_UNKNOWN "emule_udpports") (!!donkey_port+4);
    int_tag (Field_UNKNOWN "emule_version") m.emule_version;
    int64_tag (Field_UNKNOWN "emule_miscoptions1") emule_miscoptions1;
    int_tag (Field_UNKNOWN "port") !!donkey_port;
  ];      
  client_to_server_tags :=
  [
    string_tag (Field_UNKNOWN "name") (local_login ());
    int_tag (Field_UNKNOWN "version") protocol_version;
    int_tag (Field_UNKNOWN "port") !!donkey_port;
  ];      
  if Autoconf.has_zlib then
    client_to_server_tags := (int_tag 
      (Field_UNKNOWN "extended") 1)::!client_to_server_tags;
  emule_info.DonkeyProtoClient.EmuleClientInfo.tags <- [
    int_tag (Field_UNKNOWN "compression") 
      (if !!emule_compression then m.emule_compression else 0);
    int_tag (Field_UNKNOWN "udpver") m.emule_udpver;
    int_tag (Field_UNKNOWN "udpport") (!!donkey_port+4);
    int_tag (Field_UNKNOWN "sourceexchange") m.emule_sourceexchange;
    int_tag (Field_UNKNOWN "comments") m.emule_comments;
    int_tag (Field_UNKNOWN "compatibleclient") 10; 
    int_tag (Field_UNKNOWN "extendedrequest") m.emule_extendedrequest;
    int_tag (Field_UNKNOWN "features") m.emule_features;
    
  ];
  overnet_connect_tags :=
  [
    string_tag (Field_UNKNOWN "name") (local_login ());
    int_tag (Field_UNKNOWN "version") !!DonkeyProtoOvernet.overnet_protocol_connect_version; 
  ];
  overnet_connectreply_tags :=
  [
    string_tag (Field_UNKNOWN "name") (local_login ());
    int_tag (Field_UNKNOWN "version") !!DonkeyProtoOvernet.overnet_protocol_connectreply_version; 
  ]
  
let enable () =
  if not !is_enabled then 
    let enabler = ref true in
    is_enabled := true;
    network.op_network_disable <- disable enabler;
    
    if not !!enable_donkey then enable_donkey =:= true;
    
    try
(*  DonkeyClient.verbose := true; *)

(**** LOAD OTHER OPTIONS ****)
      
(* TODO INDEX      DonkeyIndexer.load_comments comment_filename; *)
(* TODO INDEX      DonkeyIndexer.install_hooks (); *)
(* TODO INDEX x CommonGlobals.do_at_exit (fun _ -> DonkeyIndexer.save_history ()); *)

(*
    BasicSocket.add_timer 10. (fun timer ->
        BasicSocket.reactivate_timer timer;
        match !indexer with
          None -> ()
        | Some (t_in, t_out) ->
            if TcpBufferedSocket.can_write t_out then begin
                TcpBufferedSocket.close t_out "timed";
                indexer := None;
              end)
*)
      
      Hashtbl.iter (fun _ file ->
          try
            if file_state file <> FileDownloaded then begin
                current_files := file :: !current_files;
(*                set_file_size file (file_size file) *)
              end else begin
                try
                  let file_disk_name = file_disk_name file in
                  if Unix32.file_exists file_disk_name &&
                    Unix32.getsize file_disk_name <> Int64.zero then begin
                      lprintf "FILE DOWNLOADED\n"; 
                      
                      DonkeyOneFile.declare_completed_file file;
                    end
                  else raise Not_found
                with _ -> 
                    file_commit (as_file file)
              end
          with e ->
              lprintf "Exception %s while recovering download %s\n"
                (Printexc2.to_string e) (file_disk_name file); 
      ) files_by_md4;
      
      let list = ref [] in
(* Normally, we should check that downloaded files are still there.  *)    
      let list = ref [] in
      List.iter (fun file ->
          
(* Hum, maybe we should not remove all these descriptions, as they might
be useful when users want to share files that they had already previously
  shared *)
          let key = (file.sh_name, file.sh_size, file.sh_mtime) in
          if Unix32.file_exists file.sh_name &&
            not (Hashtbl.mem shared_files_info key) 
            then begin
              Hashtbl.add shared_files_info key file;
              list := file :: !list
            end
      ) !!known_shared_files;
      known_shared_files =:= !list;

(**** CREATE WAITING SOCKETS ****)
      let rec find_port new_port =
        try
          let sock = TcpServerSocket.create 
              "donkey client server"
              (Ip.to_inet_addr !!client_bind_addr)
            !!donkey_port (client_connection_handler false) in
          
          TcpServerSocket.set_accept_controler sock connections_controler;
          listen_sock := Some sock;
          donkey_port =:= new_port;
          
          begin try
              let sock =
                (UdpSocket.create (Ip.to_inet_addr !!client_bind_addr)
                  (!!donkey_port + 4) 
                  (udp_handler DonkeyUdp.udp_client_handler))
              in
              udp_sock := Some sock;
              UdpSocket.set_write_controler sock udp_write_controler;
            with e ->
                lprintf "Exception %s while binding UDP socket\n"
                  (Printexc2.to_string e);
          end;
          sock
        with e ->
            if !find_other_port then find_port (new_port+1)
            else  raise e
      in
      let sock = find_port !!donkey_port in
      DonkeyProtoOvernet.Overnet.enable ();
      DonkeyProtoKademlia.Kademlia.enable ();
      
      begin
        match Unix.getsockname (BasicSocket.fd (TcpServerSocket.sock sock)) with
          Unix.ADDR_INET (ip, port) ->
            assert (!!donkey_port = port);
        | _ -> failwith "Bad socket address"
      end;
      
      let port = !!donkey_port in
      
      reset_tags ();
      
      Options.option_hook global_login reset_tags;
      Options.option_hook login reset_tags;

(**** START TIMERS ****)
      add_session_option_timer enabler check_client_connections_delay 
	(fun _ -> 
	   DonkeyUdp.extent_search ();
	   DonkeyServers.udp_query_sources ());
      
      add_session_option_timer enabler buffer_writes_delay 
        (fun _ -> Unix32.flush ());
      
      add_session_option_timer enabler check_connections_delay 
        DonkeyServers.check_server_connections;
      add_session_option_timer enabler compute_md4_delay 
        (fun _ ->
          DonkeyOneFile.check_files_downloaded ();
          DonkeyShare.check_shared_files ()
      );
      add_session_timer enabler 5.0 DonkeyServers.walker_timer;
      add_session_timer enabler 1.0 DonkeyServers.udp_walker_timer;
      
      add_session_timer enabler 3600. hourly_timer;
      add_session_timer enabler 30. halfmin_timer;
      add_session_timer enabler 300. fivemin_timer;
      add_session_timer enabler 900. quarter_timer;
      add_session_timer enabler 1. second_timer;
      add_session_timer enabler 60. (fun _ ->
          (try
              DonkeyServers.query_locations_timer ();
            with _ -> ());
          List.iter (fun file -> DonkeyShare.must_share_file file) 
          !new_shared_files;  
          new_shared_files := [];
      );
      add_session_option_timer enabler remove_old_servers_delay 
          DonkeyServers.remove_old_servers;

      DonkeyComplexOptions.load_sources ();
      
(**** START PLAYING ****)  
(* removed, just wait for timer to start the action *)
(*
    (try DonkeyUdp.force_check_locations () with _ -> ());
    (try force_check_server_connections true with _ -> ());
*)
  with e ->
      lprintf "Error: Exception %s during startup\n"
        (Printexc2.to_string e)

let _ =

(* TODO INDEX  DonkeyIndexer.init (); *)

(*
  file_ops.op_file_commit <- (fun file ->
      DonkeyInteractive.save_file file 
        (DonkeyInteractive.saved_name file);
      lprintf "SAVED\n";
);
  *)
  network.op_network_enable <- enable;
(*  network.network_config_file <- []; *)
  network.op_network_info <- (fun n ->
      { 
        network_netnum = network.network_num;
        network_config_filename = (match network.network_config_file with
            [] -> "" | opfile :: _ -> options_file_name opfile);
        network_netname = network.network_name;
        network_netflags = network.network_flags;
        network_enabled = network.op_network_is_enabled ();
        network_uploaded = Int64.zero;
        network_downloaded = Int64.zero;
        network_connected = List.length (connected_servers ());
      });
  CommonInteractive.register_gui_options_panel "eDonkey" 
    gui_donkey_options_panel;
  CommonInteractive.register_gui_options_panel "Overnet" 
    DonkeyProtoOvernet.Overnet.gui_overnet_options_panel;
  CommonInteractive.register_gui_options_panel "Kademlia" 
    DonkeyProtoKademlia.Kademlia.gui_overnet_options_panel

  
let _ =
  CommonInteractive.add_main_options
    
    [
    "-dump", Arg.String (fun file -> 
        DonkeyImport.dump_file file), " <filename> : dump file";
    "-known", Arg.String (fun file ->
        let module K = DonkeyImport.Known in
        let s = File.to_string file in
        let t = K.read s in
        K.print t;
        lprint_newline ();
    ), " <filename> : print a known.met file";
    "-part", Arg.String (fun file ->
        let module K = DonkeyImport.Part in
        let s = File.to_string file in
        let t = K.read s in
        K.print t;
        lprint_newline ();
    ), " <filename> : print a .part.met file";
    "-server", Arg.String (fun file ->
        let module K = DonkeyImport.Server in
        let s = File.to_string file in
        let t = K.read s in
        K.print t;
        lprint_newline ();
        exit 0
    ), " <filename> : print a server.met file";
    "-pref", Arg.String (fun file ->
        let module K = DonkeyImport.Pref in
        let s = File.to_string file in
        let t = K.read s in
        K.print t;
        lprint_newline ();
    ), " <filename> : print a server.met file";
  ]
