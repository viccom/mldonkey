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

open Mftp    
open Gui_types
  
type search = {
    mutable search_num : int;
    mutable search_query : search_query;
  }

type options = {
    mutable connection_port : int;
    mutable control_port : int;
    mutable gui_port : int;
    
    mutable save_options_delay : float;
    mutable check_client_connections_delay : float;
    mutable check_server_connections_delay : float;
    mutable small_retry_delay : float;
    mutable medium_retry_delay : float;
    mutable long_retry_delay : float;
    
    mutable name : string;
    mutable max_connected_servers : int;
    mutable upload_limit : int;
    mutable features : string;
    
    mutable server_timeout: float;
    mutable client_timeout: float;
    mutable max_server_age : int;
    mutable password : string;
  }

type server_key = {
    key_ip: Ip.t;
    key_port : int;
  }



type from_gui =
| ConnectMore_query
| CleanOldServers
| KillServer
| ExtendedSearch
| Password of int *  string
| Search_query of bool (* local or not *) * search
| Download_query of string list * int32 * Md4.t * (int option)
| AddServer_query of server_key
| AddNewFriend of Ip.t * int
| RemoveServer_query of server_key
| SaveOptions_query of (string * string) list (* options *)
| RemoveDownload_query of Md4.t
| ServerUsers_query of server_key
| SaveFile of Md4.t * string
| AddFriend of int
| AddUserFriend of user_info
| RemoveFriend of int
| FindFriend of string
| ViewUsers of server_key
| ConnectAll of Md4.t
| ConnectServer of server_key
| DisconnectServer of server_key
| SwitchDownload of Md4.t
| VerifyAllChunks of Md4.t
| QueryFormat of Md4.t
| ModifyMp3Tags of Md4.t * Mp3tag.tag
| ForgetSearch of int
| SetOption of string * string
| Command of string
| SayFriends of string * int list
| Preview of Md4.t
| ConnectFriend of int  
| GetServer_users of server_key
| GetClient_files of int
| GetFile_locations of Md4.t
| GetServer_info of server_key
| GetClient_info of int
| GetFile_info of Md4.t
| SendMoreInfo of Md4.t list * int list

  
and result_info = {
    mutable result_num : int;    
    mutable result_res : result;
  }

and file_info = {
    mutable file_num : int;
    mutable file_name : string list;
    mutable file_md4 : Md4.t;        
    mutable file_size : int32;
    mutable file_downloaded : int32; (* LOT OF CHANGES *)
    mutable file_nlocations : int; (* MANY CHANGES *)
    mutable file_nclients: int;
    mutable file_state : file_state;
    mutable file_chunks : string;
    mutable file_availability : string; (* MANY CHANGES *)
    mutable file_more_info : more_file_info option;
    mutable file_download_rate : float; (* LOT OF CHANGES *)
    mutable file_format : format;
  }
  
and more_file_info = {
    mutable file_known_locations : client_info list; 
    mutable file_indirect_locations : client_info list;
  }

and user_info = {
    user_md4 : Md4.t;
    user_name : string;
    user_ip : Ip.t;
    user_port : int;
    user_tags : tag list;
    user_server : server_key;
  }

and server_info = {
    server_num : int;
    mutable server_ip : Ip.t;
    mutable server_port : int;
    mutable server_score : int;
    mutable server_tags : Mftp.tag list;
    mutable server_nusers : int;
    mutable server_nfiles : int;
    mutable server_state : connection_state;
    mutable server_name : string;
    mutable server_description : string;
    mutable server_users : user_info list option;
  } 

and client_info = {
    mutable client_kind : location_kind;
(*    mutable client_md4 : Md4.t;                   *)
(*    mutable client_chunks : string;               *)
(*    mutable client_files : (Md4.t * string) list; *)
    mutable client_state : connection_state;
    mutable client_is_friend : friend_kind;
    mutable client_tags: Mftp.tag list;
    mutable client_name : string;
    mutable client_files:  result list option;
    mutable client_num : int;
    mutable client_rating : int32;
  }

and local_info = {
    mutable upload_counter : int; 
    mutable shared_files : int;
  }

type to_gui =
| Connected of int
| Options_info of (string * string) list (*  options *)
| GuiConnected
  
| Search_result of result_info
| Search_waiting of int * int
  
| File_info of file_info
| File_downloaded of int * int32 * float
| File_availability of int * string * string
| File_locations of int * client_info list * client_info list
  
| Server_busy of server_key * int * int
| Server_users of server_key * user_info list
| Server_state of server_key * connection_state
| Server_info of server_info
  
| Client_info of client_info
| Client_state of int * connection_state
| Client_friend of int * friend_kind
| Client_files of int * result list option

| LocalInfo of local_info
| Console of string
| Dialog of string * string
  

  