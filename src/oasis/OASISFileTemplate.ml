(********************************************************************************)
(*  OASIS: architecture for building OCaml libraries and applications           *)
(*                                                                              *)
(*  Copyright (C) 2008-2010, OCamlCore SARL                                     *)
(*                                                                              *)
(*  This library is free software; you can redistribute it and/or modify it     *)
(*  under the terms of the GNU Lesser General Public License as published by    *)
(*  the Free Software Foundation; either version 2.1 of the License, or (at     *)
(*  your option) any later version, with the OCaml static compilation           *)
(*  exception.                                                                  *)
(*                                                                              *)
(*  This library is distributed in the hope that it will be useful, but         *)
(*  WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY  *)
(*  or FITNESS FOR A PARTICULAR PURPOSE. See the file COPYING for more          *)
(*  details.                                                                    *)
(*                                                                              *)
(*  You should have received a copy of the GNU Lesser General Public License    *)
(*  along with this library; if not, write to the Free Software Foundation,     *)
(*  Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA               *)
(********************************************************************************)

(** Generate files with auto-generated part
    @author Sylvain Le Gall
  *)

open OASISMessage
open OASISGettext
open OASISUtils

(** {1 Comments} *)

(** Describe comment *)
type comment =
    {
      of_string: string -> string;
      regexp:    quote:bool -> string -> Str.regexp;
      start:     string;
      stop:      string;
    }

(**/**)
let (start_msg, stop_msg) =
  "OASIS_START",
  "OASIS_STOP"

let white_space =
  "[ \t]*"

let comment cmt_beg cmt_end =
  let of_string =
      match cmt_end with
        | None ->
            Printf.sprintf "%s %s" cmt_beg 
        | Some cmt_end ->
            (fun str ->
               Printf.sprintf "%s %s %s" cmt_beg str cmt_end)
  in
  let regexp ~quote str = 
    match cmt_end with 
      | Some cmt_end ->
          Str.regexp ("^"^white_space^
                      (Str.quote cmt_beg)^
                      white_space^
                      (if quote then Str.quote str else str)^
                      white_space^
                      (Str.quote cmt_end)^
                      white_space^"$")
      | None ->
          Str.regexp ("^"^white_space^
                      (Str.quote cmt_beg)^
                      white_space^
                      (if quote then Str.quote str else str)^
                      white_space^"$")
  in
    {
      of_string = of_string;
      regexp    = regexp;
      start     = of_string start_msg;
      stop      = of_string stop_msg;
    }

(**/**)

let comment_ml =
  comment "(*" (Some "*)")

let comment_sh = 
  comment "#" None

let comment_makefile = 
  comment_sh

let comment_ocamlbuild =
  comment_sh

let comment_bat = 
  comment "rem" None

let comment_meta = 
  comment_sh

(** {1 Template generation} *)

(** {1 Types} *)

type line = string

type body = 
  | NoBody
  | Body of line list
  | BodyWithDigest of Digest.t * line list

type template =
    {
      src_fn:      OASISTypes.filename;
      tgt_fn:      OASISTypes.filename option;
      comment:     comment;
      header:      line list;
      body:        body; 
      footer:      line list;
      perm:        int;
    }

(** Create a OASISFileTemplate.t
  *)
let file_make fn comment header body footer =
  {
    src_fn  = fn;
    tgt_fn  = None;
    comment = comment;
    header  = header;
    body    = Body body;
    footer  = footer;
    perm    = 0o644;
  }


(** Split a list of string containing a file template. 
  *)
let of_string_list ~template fn comment lst =

  (* Convert a Digest.to_hex string back into Digest.t *)
  let digest_of_hex s =
    let d       = String.make 16 '\000' in
    let hex_str = "0x00" in
      for i = 0 to (String.length d) - 1 do 
        hex_str.[2] <- s.[2 * i];
        hex_str.[3] <- s.[2 * i + 1];
        d.[i] <- Char.chr (int_of_string hex_str)
      done;
      d
  in

  (* Match start and stop comment *)
  let is_start, is_stop =
    let match_regexp msg =
      let rgxp =
        comment.regexp ~quote:true msg
      in
        fun str ->
          Str.string_match rgxp str 0
    in
      (match_regexp start_msg),
      (match_regexp stop_msg)
  in

  (* Match do not edit comment *)
  let do_not_edit =
    comment.regexp ~quote:false "DO NOT EDIT (digest: \\(.*\\))"
  in

  (* Separate a list into three part: header, body and footer.
     Each part should be separated by the appropriate start/stop comment.
   *)
  let header, body, footer = 
      (* Extract elem until the first that match condition.
       * The element that matched is removed 
       *)
      let rec split_cond cond acc lst =
        match lst with 
          | hd :: tl ->
              if cond hd then
                split_cond cond (hd :: acc) tl
              else
                (List.rev acc), tl
          | [] ->
              raise Not_found
      in
        (* Begin by extracting header, if that fail there
         * is no body/footer.
         *)
        try
          let lst_header, tl =
            split_cond 
              (fun str -> not (is_start str))
              []
              lst
          in
          let digest_body, tl = 
            match tl with 
              | hd :: tl when Str.string_match do_not_edit hd 0 ->
                  let digest =
                    Str.matched_group 1 hd
                  in
                    Some (digest_of_hex digest), tl
              | lst ->
                  None, lst
          in
          let lst_body, lst_footer =
            try
              split_cond 
                (fun str -> not (is_stop str))
                []
                tl
            with Not_found ->
              tl, []
          in
            match digest_body with 
              | Some d ->
                  lst_header, BodyWithDigest (d, lst_body), lst_footer
              | None ->
                  lst_header, Body lst_body, lst_footer

        with Not_found ->
          lst, NoBody, []

  in

  let res = 
    file_make 
      fn 
      comment 
      header 
      [] 
      footer
  in

    if body = NoBody then
      warning 
        (if template then
           (f_ "No replace section found in template for file %s") 
         else
           (f_ "No replace section found in file %s"))
        fn;
    {res with body = body}


(** Use a filename to extract OASISFileTemplate.t 
  *)
let of_file ~template fn comment =
 let lst =
   let chn_in =
     open_in_bin fn 
   in
   let lst =
     ref []
   in
     (
       try
         while true do
           lst := (input_line chn_in) :: !lst
         done
       with End_of_file ->
         ()
     );
     close_in chn_in;
     List.rev !lst
 in
   of_string_list ~template fn comment lst



(** Create an OCaml file template taking into account subtleties, like line
    modifier. 
  *)
let of_mlfile fn header body footer  = 

  let rec count_line str line_cur str_start =
    if str_start < String.length str then 
      (
        try 
          count_line 
            str
            (line_cur + 1)
            ((String.index_from str str_start '\n') + 1)
        with Not_found ->
          (line_cur + 1)
      )
    else
      (
        line_cur + 1
      )
  in

  (* Make sure that line modifier contains reference to file that
   * really exists. If not modify the matching string.
   *)
  let check_line_modifier str =
    let rgxp =
      Str.regexp "^#[ \\t]*[0-9]+[ \\t]+\"\\([^\"]*\\)\""
    in
    let rec check_line_modifier_aux (prev_find, prev_str, prev_idx) = 
      try
        let idx =
          Str.search_forward rgxp prev_str prev_idx
        in
        let line_modifier =
          Str.matched_string prev_str
        in
        let line_modifier_fn = 
          Str.matched_group 1 prev_str
        in
        let acc = 
          if Sys.file_exists line_modifier_fn then
            (
              (* We found a valid match, continue to search
               *)
              true, prev_str, idx + (String.length line_modifier)
            )
          else
            (
              (* The line modifier filename is not available, better
               * comment it
               *)
              let replace_regexp = 
                Str.regexp 
                  ("^"^(Str.quote line_modifier))
              in
              let line_modifier_commented =
                "(* "^line_modifier^" *)"
              in
              let str = 
                Str.global_replace 
                  replace_regexp 
                  line_modifier_commented
                  prev_str
              in
                (* Restart search before we replace the string, at this
                 * point index has not been modified.
                 *)
                prev_find, str, prev_idx
            )
        in
          check_line_modifier_aux acc
      with Not_found ->
        prev_find, prev_str, (String.length prev_str)
    in

    let find, str, _ = 
      check_line_modifier_aux (false, str, 0)
    in
      find, str
  in

  let insert_line_modifier lst line_start = 
    let rlst, line_end =
      List.fold_left
        (fun (acc, line_cur) str ->
           (* Comment useless line modifier *)
           let contains_line_modifier, validated_str =
             check_line_modifier str
           in
           let line_cur =
             count_line validated_str line_cur 0
           in
             if contains_line_modifier then
               ((Printf.sprintf "# %d %S" line_cur fn) :: validated_str :: acc), 
               (line_cur + 1)
             else
               (validated_str :: acc), 
               line_cur)
        ([], line_start)
        lst
    in
      List.rev rlst, line_end
  in

  let header, line_end =
    insert_line_modifier header 1
  in

  let body, line_end =
    (* Will add 2 lines of comments: start + digest *)
    insert_line_modifier body (line_end + 2)
  in

  let footer, _ =
    if footer <> [] then
      (* Will add 1 line of comments: stop *)
      insert_line_modifier footer (line_end + 1)
    else
      [], line_end
  in

    file_make
      fn
      comment_ml
      header
      body
      footer




(** Set the digest of body to match the current body
  *)
let digest_update t =
  {t with 
       body = 
         match t.body with 
           | NoBody -> NoBody
           | BodyWithDigest (_, lst)
           | Body lst ->
               BodyWithDigest
                 (Digest.string (String.concat "\n" lst),
                  lst)}


(** Check that the body's digest match the published digest. 
    Return true if this is the case.
  *)
let digest_check t =
  let t' = digest_update t in
    match t'.body, t.body with 
      | BodyWithDigest (d', _), BodyWithDigest (d, _) ->
          d' = d
      | _, _ ->
          true


(** [merge t_org t_new] Use header and footer from [t_org] and the rest from
    [t_new]
  *)
let merge t_org t_new =
  {t_new with 
       header = t_org.header;
       body   = 
         (if t_org.body = NoBody then
            t_org.body
          else
            t_new.body);
       footer = t_org.footer}


(** Write the target file
  *)
let to_file t = 
  (* Be sure that digest match body content *)
  let t =
    digest_update t
  in

  (* Write body, header and footer to output file. Separate
   * each part by appropriate comment and digest.
   *)
  let chn_out =
    open_out_gen
      [Open_wronly; Open_creat; Open_trunc; Open_binary]
      t.perm 
      (match t.tgt_fn with 
         | Some fn -> fn
         | None    -> t.src_fn)
  in
  let output_line str =
    output_string chn_out str;
    output_char   chn_out '\n'
  in
  let output_lst =
    List.iter output_line
  in

    output_lst t.header;
    begin 
      match t.body with 
        | NoBody ->
            ()

        | BodyWithDigest (d, lst) ->
            output_line t.comment.start;
            output_line 
              (t.comment.of_string 
                 (Printf.sprintf 
                    "DO NOT EDIT (digest: %s)"
                    (Digest.to_hex d)));
            output_lst   lst;
            output_line  t.comment.stop

        | Body lst ->
            output_line  t.comment.start;
            output_lst   lst;
            output_line  t.comment.stop
    end;
    output_lst t.footer;
    close_out chn_out


(** Generate a file using a template. Only the part between OASIS_START and 
    OASIS_END will really be replaced if the file exist. If file doesn't exist
    use the whole template.
 *)
let file_generate t = 

  (* Check that file has changed 
   *)
  let body_has_changed t_org t_new = 
    if t_org.body <> t_new.body then
      begin
        match t_org.body, t_new.body with 
          | Body lst1, Body lst2
          | BodyWithDigest (_, lst1), BodyWithDigest (_, lst2)
          | BodyWithDigest (_, lst1), Body lst2
          | Body lst1, BodyWithDigest (_, lst2) ->
              begin
                let org_fn = String.concat "\n" lst1 in
                let new_fn = String.concat "\n" lst2 in
                  (String.compare org_fn new_fn) <> 0
              end

          | b1, b2 ->
              b1 <> b2
      end
    else
      false
  in

  let fn = 
    t.src_fn
  in

    if Sys.file_exists fn then
      begin
        let t_org = 
          of_file ~template:false fn t.comment
        in

          if not (digest_check t_org) then
            begin
              let rec backup =
                function
                  | ext :: tl ->
                      let fn_backup = 
                        fn ^ ext
                      in
                        if not (Sys.file_exists fn_backup) then
                          begin
                            warning 
                              (f_ "File %s has changed, doing a backup in %s")
                              fn fn_backup;
                            FileUtil.cp [fn] fn_backup
                          end
                        else
                          backup tl
                  | [] ->
                      failwithf1
                        (f_ "File %s has changed and need a backup, \
                           but all filenames for the backup already exist")
                        fn
              in
                backup ("bak" :: (Array.to_list (Array.init 10 (Printf.sprintf "ba%d"))))
            end;

            if t.tgt_fn <> None || body_has_changed t_org t then
              begin
                (* Regenerate *)
                info (f_ "Regenerating file %s") fn;
                to_file (merge t_org t)
              end
            else
              begin
                info (f_ "File %s has not changed, skipping") fn
              end
      end
    else
      begin
        info (f_ "File %s doesn't exist, creating it.") fn;
        to_file t
      end


(** {1 Multiple templates management }
  *)

(**/**)
module S = 
  Map.Make (
struct
  type t = OASISTypes.filename

  let compare = 
    FilePath.UnixPath.compare
end)
(**/**)

exception AlreadyExists of OASISTypes.filename

type templates = template S.t

(** No generated template files
  *)
let empty =
  S.empty

(** Find a generated template file *)
let find = 
  S.find

(** Add a generated template file
    @raise AlreadyExists
  *)
let add e t = 
  if S.mem e.src_fn t then
    raise (AlreadyExists e.src_fn)
  else
    S.add e.src_fn e t

(** Add or replace a generated template file
  *)
let replace e t =
  S.add e.src_fn e t

(** Fold over generated template files
  *)
let fold f t acc =
  S.fold
    (fun k e acc ->
       f e acc)
    t 
    acc
