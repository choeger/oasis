
(** Generate files with auto-generated part
    @author Sylvain Le Gall
  *)

open OASISMessage
open OASISGettext
open OASISUtils

(** {1 Comments} *)

(** Type to describe comment *)
type comment_format =
    {
      of_string: string -> string;
      regexp:    quote:bool -> string -> Str.regexp;
      start:     string;
      stop:      string;
    }

type content =
  (* Use header * body * footer without start/stop comment *)
  | Split of (string list) * (string list) * (string list)
  (* Look for start/stop comment and split *)
  | NeedSplit of string list

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

(** Generate a file using a template. Only the part between OASIS_START and 
    OASIS_END will really be replaced if the file exist. If file doesn't exist
    use the whole template.
 *)
let file_generate ?(target) fn comment content = 

  (* Match start and stop comment
   *)
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

  let do_not_edit =
    comment.regexp ~quote:false "DO NOT EDIT (digest: \\(.*\\))"
  in

  (* Compute the digest of a list
   *)
  let digest_of_list lst =
    Digest.to_hex 
      (Digest.string 
         (String.concat "\n" lst))
  in

  (* Write body, header and footer to output file. Separate
   * each part by appropriate comment and digest.
   *)
  let output_file lst_header lst_body lst_footer =
    let chn_out =
      open_out_bin 
        (match target with 
           | Some fn -> fn
           | None    -> fn)
    in
    let output_line str =
      output_string chn_out str;
      output_char   chn_out '\n'
    in
    let output_lst =
      List.iter
        output_line
    in

      output_lst   lst_header;
      output_line  comment.start;
      output_line 
        (comment.of_string 
           (Printf.sprintf 
              "DO NOT EDIT (digest: %s)"
              (digest_of_list lst_body)));
      output_lst   lst_body;
      output_line  comment.stop;
      output_lst   lst_footer;
      close_out chn_out
  in

  (* Check that file has changed 
   *)
  let file_has_changed (old_header, old_body, old_footer) (new_header, new_body, new_footer) = 
    let old_fn =
      String.concat "\n" (List.flatten [old_header; old_body; old_footer])
    in
    let new_fn = 
      String.concat "\n" (List.flatten [new_header; new_body; new_footer])
    in
      (String.compare old_fn new_fn) <> 0
  in

  (* Separate a list into three part: header, body and footer.
   * Each part is separated by the appropriate start/stop comment.
   *)
  let split_header_body_footer lst = 
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
                  Some digest, tl
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
          lst_header, Some (digest_body, lst_body, lst_footer)
      with Not_found ->
        lst, None
  in

  (* Split content
   *)
  let content_header,
      content_body,
      content_footer =

    match content with
      | Split (lst_header, lst_body, lst_footer) ->
          lst_header, lst_body, lst_footer
      | NeedSplit lst ->
          begin
            match split_header_body_footer lst with
              | lst_header, Some (_, lst_body, lst_footer) ->
                  lst_header, lst_body, lst_footer
              | lst_header, None ->
                  warning 
                    (f_ "No replace section found in template for file %s") 
                    fn;
                  lst_header, [], []
          end
  in

    if Sys.file_exists fn then
      begin
        let lst_fn =
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

        (* Actual split file content
         *)
          match split_header_body_footer lst_fn with 
            | fn_header, Some (digest_body, fn_body, fn_footer) ->
                begin
                  (* Check "do not digest" value
                   *)
                  let () =
                    match digest_body with
                      | Some expected_digest ->
                          begin
                            let digest =
                              digest_of_list fn_body
                            in
                              if expected_digest <> digest then 
                                begin
                                  let fn_backup =
                                    fn^".bak"
                                  in
                                    warning 
                                      (f_ "File %s has changed, doing a backup in %s")
                                      fn fn_backup;
                                    if not (Sys.file_exists fn_backup) then
                                      FileUtil.cp [fn] fn_backup
                                    else
                                      failwithf1
                                        (f_ "File %s already exists")
                                        fn_backup
                                end

                          end
                      | lst ->
                          ()
                  in
                    if target <> None || file_has_changed ([], fn_body, []) ([], content_body, []) then
                      begin
                        (* Regenerate *)
                        info (f_ "Regenerating file %s") fn;
                        output_file 
                          fn_header
                          content_body
                          fn_footer
                      end
                    else
                      begin
                        info (f_ "File %s has not changed, skipping") fn
                      end
                end
            | fn_header, None ->
                begin
                  warning (f_ "No replace section in file %s") fn;
                  match target with
                    | Some fn ->
                        (
                          (* We still generate file since it is not the same as
                           * source file 
                           *)
                          let chn =
                            open_out_bin fn
                          in
                            List.iter
                              (fun str ->
                                 output_string chn str;
                                 output_char   chn '\n')
                              fn_header;
                            close_out chn
                        )
                    | None ->
                        ()
                end
      end
    else
      begin
        info (f_ "File %s doesn't exist, creating it.") fn;
        output_file 
          content_header 
          content_body
          content_footer
      end

let mlfile_generate ?(target) fn content = 

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

  let content =
    match content with 
      | Split (lst_header, lst_body, lst_footer) ->
          let lst_header, line_end =
            insert_line_modifier lst_header 1
          in
          let lst_body, line_end =
            (* Will add 2 lines of comments: start + digest *)
            insert_line_modifier lst_body (line_end + 2)  
          in
          let lst_footer, _ =
            (* Will add 1 line of comments: stop *)
            insert_line_modifier lst_footer (line_end + 1)
          in
            Split (lst_header, lst_body, lst_footer)
          
      | NeedSplit lst ->  
          NeedSplit (fst (insert_line_modifier lst 0))
  in

    file_generate ?target fn comment_ml content
