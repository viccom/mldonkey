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

open Options
open Mftp
open BasicSocket
open TcpClientSocket
open Unix
open Gui_proto
open Gui_types
open Gui_options
module O = Gui_options
module M = Gui_messages
open MyCList
open Gui_handler  
open Gui
      
let ko = Int32.of_int 1024
  
let unit_of_string s =
  match String.lowercase s with
    "mo" -> Int32.mul ko ko
  | "ko" -> ko
  | _ -> Int32.one

let search_media_list = 
  [ "Program", "Pro";
    "Documentation", "Doc";
    "Collection", "Col";
  ]
  
let search_format_list = []

let option_of_string s =
  if s = "" then None else Some s
  
let submit_search (gui: gui) local ()=
  let module P = Gui_proto in
  incr search_counter;
  let search_num = !search_counter in
  current_search := !search_counter;
  nresults := 0;
  update_searches_label ();
  let s = gui#tab_searches in
  gui_send (P.Search_query (local, 
      { 
        P.search_query =
        {
          search_max_hits = int_of_string s#combo_max_hits#entry#text;
          search_words = String2.tokens s#entry_search_words#text;
          search_minsize = (let minsize = s#entry_search_minsize#text in
            if minsize = "" then None else Some (
                Int32.mul (Int32.of_string minsize)
                (unit_of_string s#combo_search_minsize_unit#entry#text)
              ));
          search_maxsize = (let maxsize = s#entry_search_maxsize#text in
            if maxsize = "" then None else Some (
                Int32.mul (Int32.of_string maxsize)
                (unit_of_string s#combo_search_minsize_unit#entry#text)
              ));
          search_avail = None;
          search_media = (
            let media = s#combo_search_media#entry#text in
            try
              Some (List.assoc media  search_media_list)
            with _ -> 
                if media = "" then None else Some media);
          search_format = (
            let format = s#combo_format#entry#text in
            try
              Some (List.assoc format search_format_list)
            with _ -> 
                if format = "" then None else Some format);
          search_min_bitrate = ( 
            let bitrate = s#combo_min_bitrate#entry#text in
            if bitrate = "" then None else
            try
              Some (Int32.of_string bitrate)
            with _ -> None);    
          search_title = option_of_string s#entry_title#text;
          search_artist = option_of_string s#entry_artist#text;
          search_album = option_of_string s#entry_album#text;
          search_fields = [];
        };
        P.search_num = !search_counter;
      }));
  let new_tab = new box_search () in

  let clist_search = MyCList.create gui new_tab#clist_search_results       
      [
(* SIZE *)
      (fun r -> (Printf.sprintf "%10s" (Int32.to_string r.result_size)));
(* NAME *)
      (fun r -> (*short_name*) (first_name r)) ;
(* FORMAT *)      
      (fun r -> r.result_format);
(* TAGS *)
      (fun r -> string_of_tags r.result_tags);
(* MD4 *)
      (fun r -> Md4.to_string r.result_md4);
    ] 
    
  in
  MyCList.set_can_select_all clist_search;
  MyCList.set_size_callback clist_search (fun n ->
      if search_num = !current_search then begin
          nresults := n; update_searches_label ()
        end);
  MyCList.set_selected_callback clist_search (fun _ r ->
      tab_searches#label_file_comment#set_text (
        match r.result_comment with
          None -> ""
        | Some comment ->
            Printf.sprintf "%s COMMENT: %s" (first_name r) comment
      ));
  MyCList.set_context_menu clist_search search_make_menu;
  ignore (new_tab#button_search_download#connect#clicked 
      (search_download clist_search gui));
  ignore (new_tab#button_stop#connect#clicked 
      (search_stop clist_search gui !search_counter));
  ignore (new_tab#button_close#connect#clicked 
      (search_close clist_search gui !search_counter));
  let label_query = new_tab#label_query in
  Hashtbl.add searches !search_counter (clist_search, label_query);
  let n = add_search_page clist_search in
  tab_searches#notebook_results#append_page 
    ~tab_label:(GMisc.label ~text:(
      Printf.sprintf "Search %d" !search_counter) ())#coerce
    new_tab#coerce;
  tab_searches#notebook_results#goto_page n

let clean_gui _ =
  gui#label_connect_status#set_text "Not connected";
  MyCList.clear clist_servers;
  MyCList.clear clist_downloads;
  MyCList.clear clist_downloaded;
  MyCList.clear clist_friends;
  MyCList.clear clist_server_users;
  MyCList.clear clist_friend_files;
  MyCList.clear clist_file_locations;
  Hashtbl.clear locations;
  Hashtbl.clear searches;
  (let text = gui#tab_console#text in
    text#delete_text 0 (text#length));
  (let text = gui#tab_friends#text_dialog in
    text#delete_text 0 (text#length));
  nconnected_servers := 0;
  ndownloaded := 0;
  ndownloads := 0;
  current_file := None;
  current_friend := -1;
  update_server_label ();
  update_download_label ();
  ignore (update_current_file ())
  
let disconnect gui = 
  match !connection_sock with
    None -> ()
  | Some sock ->
      clean_gui ();
      TcpClientSocket.close sock "user close";
      connection_sock := None

let reconnect gui =
  (try disconnect gui with _ -> ());
  clean_gui ();
  let sock = TcpClientSocket.connect 
      (try
        let h = Unix.gethostbyname 
            (if !!hostname = "" then Unix.gethostname () else !!hostname) in
        h.Unix.h_addr_list.(0)
      with 
        e -> 
          Printf.printf "Exception %s in gethostbyname" (Printexc.to_string e);
          print_newline ();
          try 
            inet_addr_of_string !!hostname
          with e ->
              Printf.printf "Exception %s in inet_addr_of_string" 
                (Printexc.to_string e);
              print_newline ();
              raise Not_found
    )
    !!port (fun _ _ -> 
        ()) in
  try
    connection_sock := Some sock;
    TcpClientSocket.set_closer sock (fun _ _ -> 
        match !connection_sock with
          None -> ()
        | Some s -> 
            if s == sock then begin
                connection_sock := None;
                clean_gui ();      
              end
    );
    TcpClientSocket.set_reader sock (value_handler (value_reader gui));
    gui#label_connect_status#set_text "Connecting"
  with e ->
      Printf.printf "Exception %s in connecting" (Printexc.to_string e);
      print_newline ();
      TcpClientSocket.close sock "error";
      connection_sock := None

let servers_connect_more (gui : gui) () =
  gui_send (Gui_proto.ConnectMore_query)
  
let servers_addserver (gui : gui) () = 
  let module P = Gui_proto in
  gui_send (P.AddServer_query {
      P.key_ip = Ip.of_string gui#tab_servers#entry_servers_new_ip#text;
      P.key_port = int_of_string gui#tab_servers#entry_servers_new_port#text;
    });
  tab_servers#entry_servers_new_ip#set_text "";
  tab_servers#entry_servers_new_port#set_text ""

  
let friends_addfriend (gui : gui) () = 
  gui_send (AddNewFriend (Ip.of_string
        gui#tab_friends#entry_friends_new_ip#text,
      int_of_string gui#tab_friends#entry_friends_new_port#text));
  tab_friends#entry_friends_new_ip#set_text "";
  tab_friends#entry_friends_new_port#set_text ""

let set_hpaned (hpaned : GPack.paned) prop =
  let (w1,_) = Gdk.Window.get_size hpaned#misc#window in
  let ndx1 = (w1 * !!prop) / 100 in
  hpaned#child1#misc#set_geometry ~width: ndx1 ();
  hpaned#child2#misc#set_geometry ~width: (w1 - ndx1 - hpaned#handle_size) ()

let set_vpaned (hpaned : GPack.paned) prop =
  let (_,h1) = Gdk.Window.get_size hpaned#misc#window in
  let ndy1 = (h1 * !!prop) / 100 in
  hpaned#child1#misc#set_geometry ~height: ndy1 ();
  hpaned#child2#misc#set_geometry ~height: (h1 - ndy1 - hpaned#handle_size) ()
  
let save_gui_options () =
(* Compute layout *)
  let (w,h) = Gdk.Window.get_size gui#coerce#misc#window in
  gui_width =:= w;
  gui_height =:= h;
  
  Options.save_with_help mldonkey_gui_ini  

let get_hpaned (hpaned: GPack.paned) prop =
  
  ignore (hpaned#child1#coerce#misc#connect#size_allocate
      ~callback: (fun r ->
        let (w1,_) = Gdk.Window.get_size hpaned#misc#window in
        prop =:= r.Gtk.width * 100 / (max 1 (w1 - hpaned#handle_size));
        save_gui_options ()
    ))

let get_vpaned (hpaned: GPack.paned) prop =
  
  ignore (hpaned#child1#coerce#misc#connect#size_allocate
      ~callback: (fun r ->
        let (_,h1) = Gdk.Window.get_size hpaned#misc#window in
        prop =:= r.Gtk.height * 100 / (max 1 (h1 - hpaned#handle_size));
        save_gui_options ()
    ))
  
let save_options (gui: gui) () =
  let module P = Gui_proto in
  let options = tab_options in

    port =:= int_of_string options#entry_options_gui_port#text;
    password =:= options#entry_options_password#text;
    hostname =:= tab_options#entry_server_hostname#text;
    try
      gui_send (P.SaveOptions_query (List.map (fun 
              (name, widget) -> name, widget#text   
          ) options_assocs ));
      save_gui_options ()
    with _ ->
        Printf.printf "ERROR SAVING OPTIONS (but port/password/host correctly set for GUI)"; print_newline ()
      
let servers_remove (gui : gui) () = 
  let module P = Gui_proto in
  for_selection clist_servers (fun s ->
      gui_send (P.RemoveServer_query (server_key s));
  ) ()