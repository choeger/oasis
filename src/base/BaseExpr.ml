
(** Conditional expression like in OASIS.
    @author Sylvain Le Gall
  *)

open BaseEnv;;

type t =
  | Bool of bool
  | Not of t
  | And of t * t
  | Or of t * t
  (* TODO: use a var here *)
  | Flag of string
  | Test of string * string
;;

type 'a choices = (t * 'a) list
;;

(** Evaluate expression *)
let rec eval =
  function
    | Bool b ->
        b

    | Not e -> 
        not (eval e)

    | And (e1, e2) ->
        (eval e1) && (eval e2)

    | Or (e1, e2) -> 
        (eval e1) || (eval e2)

    | Flag nm ->
        let v =
          var_get nm
        in
          assert(v = "true" || v = "false");
          (v = "true")

    | Test (nm, vl) ->
        let v =
          var_get nm
        in
          (v = vl)
;;

let choose lst =
  let rec choose_aux = 
    function
      | (cond, vl) :: tl ->
          if eval cond then 
            vl 
          else
            choose_aux tl
      | [] ->
          failwith 
            "No result for a choice list"
  in
    choose_aux (List.rev lst)
;;

let singleton e = 
  [Bool true, e]
;;

(* END EXPORT *)

open OASISTypes;;

(** Convert OASIS expression 
  *)
let rec expr_of_oasis =
  function 
    | EBool b       -> Bool b
    | ENot e        -> Not (expr_of_oasis e)
    | EAnd (e1, e2) -> And(expr_of_oasis e1, expr_of_oasis e2)
    | EOr (e1, e2)  -> Or(expr_of_oasis e1, expr_of_oasis e2)
    | EFlag s       -> Flag s
    | ETest (TOs_type, s)       -> Test("os_type", s)
    | ETest (TSystem, s)        -> Test("system", s)
    | ETest (TArchitecture, s)  -> Test("architecture", s)
    | ETest (TCcomp_type, s)    -> Test("ccomp_type", s)
    | ETest (TOCaml_version, s) -> Test("ocaml_version", s)
;;

(** Convert an OASIS choice list to BaseExpr.choices
  *)
let choices_of_oasis lst =
  List.map
    (fun (e, v) -> expr_of_oasis e, v)
    lst
;;

open ODN;;

(** Convert BaseExpr.t to pseudo OCaml code 
  *)
let rec code_of_expr e =
  let cstr, args =
    match e with 
      | Bool b ->
          "Bool", [BOO b]
      | Not e ->
          "Not", [code_of_expr e]
      | And (e1, e2) ->
          "And", [code_of_expr e1; code_of_expr e2]
      | Or (e1, e2) ->
          "Or", [code_of_expr e1; code_of_expr e2]
      | Flag nm ->
          "Flag", [STR nm]
      | Test (nm, vl) ->
          "Test", [STR nm; STR vl]
  in
    VRT ("BaseExpr."^cstr, args)
;;

(** Convert BaseExpr.choices to pseudo OCaml code
  *)
let code_of_choices code_of_elem lst =
  LST
    (List.map
       (fun (expr, elem) ->
          TPL [code_of_expr expr; code_of_elem elem])
       lst)
;;

(** Convert "bool BaseExpr.choices" to pseudo OCaml code
  *)
let code_of_bool_choices =
  code_of_choices (fun v -> BOO v) 
;;

(** Always true condition 
  *)
let condition_true =
  [Bool true, true]
;;

(** Code of always true condition
  *)
let code_condition_true =
  code_of_bool_choices condition_true
;;
