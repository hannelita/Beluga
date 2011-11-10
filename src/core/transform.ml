open Syntax
open Substitution
open Id
open Ast
open Pretty
(**

   @author Marie-Andree B.Langlois
*)

module Loc = Syntax.Loc
let out_channel = open_out "reconstruct.out";

exception Error of string

let printLocation loc = Parser.Grammar.Loc.print Format.std_formatter loc

(* Terminal and Helper Functions Section *)

(* create terminals and then check if a symbol was declared terminal *)
(* terminal list -> string list *)
let rec makeTerminals lt =
  match lt with
    | [] -> []
    | h :: t -> let Terminal(_, t1) = h in t1 :: (makeTerminals t)

(* string -> string list -> bool *)
let rec checkString s lt = 
  match lt with 
    | [] -> false
    | h :: t -> if h = s then true else checkString s t

type jdef = Jdef of string * string list

let rec findJu s lju= 
  match lju with 
    | [] -> Jdef("",[])
    | (Jdef(s1, lsym))::t -> if checkString s lsym then Jdef(s1, lsym) else findJu s t

let checkNil lt = 
  match lt with 
    | [] -> true
    | h :: t -> false

let rec printL l =
  match l with 
    | [ ] -> ( )
    | h::t -> output_string out_channel h; output_string out_channel "print list \n"; printL t

type bind = Paire of alternative * string list


(* Declaration section *)

let rec findBind l a lv ac =
  match a with
    | AltAtomic(l1,t1,a1) -> (begin match a1 with
                                | None -> let s = locToString(l) in let s1 = s ^ "This alternative needs a variable binding." in raise (Error (s1))
                                | Some(a2) -> if checkString t1 lv then findBind l a2 lv (t1::ac) 
                                              else let s1 = "Did you forget to declare " ^ t1 ^ " as a variable?" in raise (Error (s1)) 
                              end )
    | AltBin(l1, a) -> output_string out_channel "found bin \n"; Paire(AltBin(l1, a), ac) 
    | _ -> let s = locToString(l) in let s1 = s ^ "Syntax error in alternative." in raise (Error (s1))

let rec altList l ty lty lt lv llam la =
  match la with
    | [] -> let s = locToString(l) in let s1 = s ^ "Can't have empty list here according to parser." in raise (Error (s1))
    | h::[] -> alts l ty lty lt lv llam h
    | h::t -> Ext.LF.ArrTyp(l, alts l ty lty lt lv llam h, altList l ty lty lt lv llam t)

(* this is for any alternative *)
(* Loc.t -> string -> string list -> terminal list -> alternative list -> Ext.LF.typ *)
and alts l ty lty lt lv llam a = 
  match a with
    | AltAtomic(l1, t1, a1) -> if (checkString t1 lty ) then
                                  (* this is a type is theres is an alternative after it just skip to next*)
                                  ( begin match a1 with
                                      | None -> Ext.LF.Atom(l1, Id.mk_name (Id.SomeString ty),Ext.LF.Nil)
                                      | Some(a2) -> output_string out_channel "AltAtomic typ \n"; 
                                                    (*alts l1 ty lty lt lv llam a2 *) (* try to remember why it was implemented this way in the first place*)
                                                    Ext.LF.ArrTyp(l,Ext.LF.Atom(l1, Id.mk_name (Id.SomeString t1),Ext.LF.Nil), alts l1 ty lty lt lv llam a2)
                                    end )
                                  else(* if (checkString t1 lt) then *)
                                  ( begin match a1 with
                                      | None -> Ext.LF.Atom(l1, Id.mk_name (Id.SomeString ty),Ext.LF.Nil)
                                      | Some(a2) -> Ext.LF.ArrTyp(l,Ext.LF.Atom(l1, Id.mk_name (Id.SomeString t1),Ext.LF.Nil), alts l1 ty lty lt lv llam a2)
                                    end ) 
                                 (* else raise (Error ("Alternatives must be only types or terminals"))*)

    | AltLam(l1, AName(t1), a1) -> output_string out_channel "alts AltLam \n";
                                        if checkString t1 lt then
                                        (begin match a1 with
                                           | None -> let s = locToString(l1) in let s1 = s ^ "Must indicate variable binding in this alternative" in raise (Error (s1))
                                           | Some(a2) ->  let Paire(a3, lv1) = findBind l a2 lv [] in alts l1 ty lty lt lv1 (t1::llam) a3
                                        end) 
                                        else let s = locToString(l1) in let s1 = s ^ " " ^ t1 ^ " was not declared terminal" in raise (Error (s1) )

    | AltFn(l1, Typ(l2, t1), t_or_l, a1) -> (begin match t_or_l with
                                                  | Ty(Typ(l3, t2)) -> (begin match a1 with 
                                                                          | None -> output_string out_channel "altfn Ty(typ)) None\n"; Ext.LF.Atom(l1, Id.mk_name(Id.SomeString t2),Ext.LF.Nil)
                                                                          | Some(a2) -> output_string out_channel "altfn Ty(typ)) Some \n"; 
                                                                                        Ext.LF.ArrTyp(l, Ext.LF.Atom(l1, Id.mk_name(Id.SomeString t2),Ext.LF.Nil), alts l1 ty lty lt lv llam a2)  
                                                                       end)
                                                  | La(la2) -> (begin match a1 with 
                                                                  | None -> output_string out_channel "altfn La(la)) None\n";
                                                                            Ext.LF.ArrTyp(l,Ext.LF.ArrTyp(l,Ext.LF.Atom(l1, Id.mk_name (Id.SomeString t1),Ext.LF.Nil), 
                                                                            altList l1 ty lty lt lv llam la2), Ext.LF.Atom(l1, Id.mk_name (Id.SomeString ty),Ext.LF.Nil))
                                                                  | Some(a2) -> output_string out_channel "altfn La(la)) Some\n";
                                                                                let Ext.LF.ArrTyp(l4,ar1,ar2) = alts l1 ty lty lt lv llam (AltFn(l1,Typ(l2, t1), t_or_l, None)) in
                                                                                Ext.LF.ArrTyp(l,ar1,alts l1 ty lty lt lv llam a2)
                                                                            
                                                                end)
                                               end )


    | AltBin(l1, a) -> output_string out_channel "AltBin\n"; alts l1 ty lty lt lv llam a

    | AltOft(l1, a1, a2) -> alts l1 ty lty lt lv llam a2 
    | _ -> raise (Error ("Unvalid alternative/Not implemented yet"))

(* this is for the first element at the begginig of an alternative *)
(* Loc.t -> string -> terminal list alternative list -> Ext.Sgn.decl list *)
let rec sgnAlts l ty lty lt lv llam la = 
  match la with
    | [] -> []
    | AltAtomic(l1, t1, a1)::t -> output_string out_channel "sgn AltAtomic \n";
                                  if (checkString t1 lty ) then
                                  (* skip to next and dont care about this type, we are at the beggining of the alternative so there cant be only this atom*)
                                  ( begin match a1 with
                                      | None -> let s = locToString(l1) in let s1 = s ^ "Illegal alternative" in raise (Error (s1))
                                      | Some(a2) -> output_string out_channel "sgn AltAtomic typ\n"; 
                                                    Ext.Sgn.Const(l1, Id.mk_name (Id.SomeString t1), alts l1 ty lty lt lv llam a2)::sgnAlts l ty lty lt lv llam t 
                                    end )
                                  else if (checkString t1 lt) then 
                                  ( begin match a1 with
                                      | None -> Ext.Sgn.Const(l1, Id.mk_name (Id.SomeString t1), Ext.LF.Atom(l, Id.mk_name (Id.SomeString ty),Ext.LF.Nil))::sgnAlts l ty lty lt lv llam t
                                      | Some(a2) -> output_string out_channel "sgn altAtomic terminal \n"; 
                                                    Ext.Sgn.Const(l1, Id.mk_name (Id.SomeString t1), Ext.LF.ArrTyp(l,
                                                    Ext.LF.Atom(l1, Id.mk_name (Id.SomeString ty),Ext.LF.Nil), alts l1 ty lty lt lv llam a2))::sgnAlts l ty lty lt lv llam t 
                                    end )
                                   else ( begin match a1 with
                                      | None -> (*Ext.Sgn.Const(l1, Id.mk_name (Id.SomeString t1), Ext.LF.Atom(l, Id.mk_name (Id.SomeString ty),Ext.LF.Nil))::*)sgnAlts l ty lty lt (lv@[t1]) llam t
                                      | Some(a2) -> let s = locToString(l1) in 
                                                    let s1 = s ^ " An Alternative must start with a terminal or declare a variable, maybe you forgot to declare " ^ t1 ^ " terminal."
                                                    in raise (Error (s1))
                                    end )

    | AltLam(l1, AName(t1), a1)::t -> output_string out_channel "sgn AltLam print list of variables\n"; printL lv; if checkString t1 lt 
                                      then 
                                      (begin match a1 with
                                           | None -> raise (Error ("Must indicate variable binding in this alternative"))
                                           | Some(a2) ->  let Paire(a3, lv1) = findBind l a2 lv [] in 
                                                          Ext.Sgn.Const(l1, Id.mk_name (Id.SomeString t1), alts l1 ty lty lt lv1 llam a3)::sgnAlts l ty lty lt lv (t1::llam) t
                                        end) 
                                      else let s = locToString(l1) in let s1 = s ^ " " ^ t1 ^ " was not declared terminal" in raise (Error (s1) )
                                      

    (*| AltFn(l1, Typ(l2, t1), Ty(Typ(l3, t2)), a1)::t ->  Ext.Sgn.Const(l, Id.mk_name (Id.SomeString ty), 
                                                 Ext.LF.ArrTyp(l,Ext.LF.Atom(l1, Id.mk_name (Id.SomeString t1),Ext.LF.Nil), 
                                                 Ext.LF.Atom(l1, Id.mk_name (Id.SomeString t2),Ext.LF.Nil)))::sgnAlts l ty lty lt lv llam t (** come up with example that uses a1 *) *)
    | AltLet(l1, a1, a2, a3)::t -> output_string out_channel "sgn AltLet \n"; 
                                      (begin match a3 with
                                           | AltFn(_) -> Ext.Sgn.Const(l1, Id.mk_name (Id.SomeString "letv"), Ext.LF.ArrTyp(l, Ext.LF.Atom(l1, Id.mk_name (Id.SomeString ty),Ext.LF.Nil), 
                                                         alts l1 ty lty lt lv llam a3))::sgnAlts l ty lty lt lv llam t
                                           | _ -> let s = locToString(l1) in let s1 = s ^ "Unvalid alternative" in raise (Error (s1))
                                        end)

    | AltPar::t ->  sgnAlts l ty lty lt lv llam t
    | _ -> let s = locToString(l) in let s1 = s ^ "Unvalid start of alternative" in raise (Error (s1))

(* string list -> string list -> production list -> Ext.Sgn.decl list, first list types second terminals *)
let rec sgnTypes lt lty lp =
  match lp with
    | [] -> []
    | Production(l1, Typ(l2, t1), la)::t -> [Ext.Sgn.Typ(l1, Id.mk_name (Id.SomeString t1), Ext.LF.Typ(l1))]@ sgnAlts l2 t1 lty lt [] [] la @ sgnTypes lt lty t

(* Judgment Section *)

(* Loc.t -> string -> judge list -> string list -> Ext.Sgn.decl list *)
let rec typ_or_sym l js ltyp =
  match js with
    | [] -> output_string out_channel "typ or sym [] \n"; Ext.LF.Typ(l) 
    | h::t -> let Judge(l1,s1) = h in if (checkString s1 ltyp ) then (output_string out_channel " typ or sym then \n"; 
                                   Ext.LF.ArrKind(l, Ext.LF.Atom(l1, Id.mk_name(Id.SomeString s1),Ext.LF.Nil), typ_or_sym l1 t ltyp) )
                                   else (output_string out_channel " typ or sym else \n"; typ_or_sym l1 t ltyp)

(* checks the judgement if its not a type its a symbol indicating the syntax of the judgement *)
(* judge list -> string list -> string list *)
let rec typ_or_sym_list lj ltyp = 
  match lj with
    | [] -> output_string out_channel "typ or sym list [] \n"; ["="]
    | h::t -> let Judge(l1,s1) = h in if (checkString s1 ltyp ) then (output_string out_channel s1; output_string out_channel " check string then \n"; 
              typ_or_sym_list t ltyp) else (output_string out_channel s1; output_string out_channel " check string else \n"; s1 :: typ_or_sym_list t ltyp  )

(* Loc.t -> jName -> jSyntax -> string list -> (string list , Ext.Sgn.decl list) *)
let sgnJudge l jn js ltyp =
   let JName(j) = jn in let JSyntax(l, a, lj) = js in ( typ_or_sym_list lj ltyp, Ext.Sgn.Typ(l,Id.mk_name (Id.SomeString j), typ_or_sym l lj ltyp))


let rec valtslist lva =
  match lva with 
    | [] -> None
    | VAltAtomic(l, s, None)::t -> Some(VAltAtomic(l, s, valtslist t ))
    | VAltFn(l1, VName(n1), VLa([va1]), None)::t -> Some(VAltFn(l1, VName(n1), VLa([va1]), valtslist t))
    | _ -> raise (Error ("Oops never thaught this case will show up"))
    
(* Loc.t -> string list -> var_alternative -> Ext.LF.spine *)
let rec valtsPar l lsym a =
  match a with 
    | VAltAtomic(l, s, vao) -> (begin match vao with 
                                 | None -> output_string out_channel "valtsPar none in altpar \n";
                                           Ext.LF.Root(l, Ext.LF.Name(l, Id.mk_name(Id.SomeString s)), Ext.LF.Nil)

                                 | Some(VAltBin(l2, va)) -> if checkString s lsym 
                                                            then (output_string out_channel s; output_string out_channel "valtspar some valtbin then \n"; raise (Error ("Error in Lamdba term."))) 
                                                            else (output_string out_channel s; output_string out_channel " valtspar some valtbin else \n";
                                                                 Ext.LF.Lam(l2, Id.mk_name(Id.SomeString s), valtsPar l lsym va) )

                                 | Some(va) -> output_string out_channel "valtspar some then in altpar \n";  
                                              Ext.LF.Root(l, Ext.LF.Name(l, Id.mk_name(Id.SomeString s)), valts l lsym va) 

                              end)


    | VAltLam(l, AName(n), va) -> output_string out_channel "valts par valtlam\n";
                                  Ext.LF.Root(l, Ext.LF.Name(l, Id.mk_name(Id.SomeString n)), valts l lsym va)

    | VAltFn(l1, VName(n1), VLa(lva), vao) -> output_string out_channel n1; output_string out_channel " valtspar valtfn\n"; (**assuming only 1 element in list *) let Some(va1) = valtslist lva in
                                                (begin match vao with
                                                   | None -> Ext.LF.Root(l1, Ext.LF.Name(l1, Id.mk_name(Id.SomeString n1)), valts l1 lsym va1)
                                                   | Some(VAltBin(l2, va)) -> output_string out_channel " valtspar valtfn valtbin else \n";
                                                                              Ext.LF.Lam(l2, Id.mk_name(Id.SomeString n1), Ext.LF.Root(l, Ext.LF.Name(l, Id.mk_name(Id.SomeString n1)), valts l1 lsym va1))(*, valts l1 lsym va)*)


                                                   | Some(a2) -> Ext.LF.Root(l1, Ext.LF.Name(l1, Id.mk_name(Id.SomeString n1)), valts l1 lsym a2)
                                                 end)

    | VAltLet(l, va) -> output_string out_channel " valts valtfn\n"; 
                             Ext.LF.Root(l, Ext.LF.Name(l, Id.mk_name(Id.SomeString "letv")), valts l lsym va)

    | _ -> let s = locToString(l) in let s1 = s ^ "Not implemented yet (in valtsPar)." in raise (Error (s1)) 

(* Loc.t -> string list -> var_alternative -> Ext.LF.spine *)
and valts l lsym va =
  match va with 
    | VAltAtomic(l, s, vao) -> (begin match vao with 
                                 | None -> if checkString s lsym 
                                           then (output_string out_channel s; output_string out_channel " valts none then \n"; Ext.LF.Nil ) 
                                           else (output_string out_channel s; output_string out_channel " valts none else \n";
                                                   Ext.LF.App(l, Ext.LF.Root(l, Ext.LF.Name(l, Id.mk_name(Id.SomeString s)), Ext.LF.Nil), Ext.LF.Nil) )

                                 | Some(VAltBin(l2, va)) -> if checkString s lsym 
                                                            then (output_string out_channel s; output_string out_channel " valts some valtbin then \n"; raise (Error ("Error in Lamdba term."))) 
                                                            else (output_string out_channel s; output_string out_channel " valts some valtbin else \n"; 
                                                            (begin match va with (** mght want to make a function instead*)
                                                               | VAltFn(l3,v2,vl2,Some(VAltBin(l4,vaoo))) -> Ext.LF.App(l, Ext.LF.Lam(l2, Id.mk_name(Id.SomeString s), 
                                                                                                             valtsPar l lsym (VAltFn(l3,v2,vl2,None))), Ext.LF.App(l, 
                                                                                                             Ext.LF.Lam(l4, Id.mk_name(Id.SomeString s), valtsPar l4 lsym vaoo), Ext.LF.Nil))
                                                               | _ -> Ext.LF.App(l, Ext.LF.Lam(l2, Id.mk_name(Id.SomeString s), valtsPar l lsym va), Ext.LF.Nil)
                                                             end)  )
 

                                 | Some(va) -> if checkString s lsym 
                                              then (output_string out_channel s; output_string out_channel "valts some then \n"; valts l lsym va) 
                                              else (output_string out_channel s; output_string out_channel " valts some else \n";
                                                   Ext.LF.App(l, Ext.LF.Root(l, Ext.LF.Name(l, Id.mk_name(Id.SomeString s)), Ext.LF.Nil), valts l lsym va) )

                              end)

    | VAltPar(l, a, vao) -> (begin match vao with 
                                 | None -> output_string out_channel "valts altpar none \n";
                                                   Ext.LF.App(l, valtsPar l lsym a, Ext.LF.Nil) 


                                 | Some(vb) -> output_string out_channel "valts altpar some \n";
                                                   Ext.LF.App(l, valtsPar l lsym a, valts l lsym vb) 

                              end)


    | VAltLam(l, AName(n), va) -> output_string out_channel "valts valtlam\n";
                                  Ext.LF.App(l, Ext.LF.Root(l, Ext.LF.Name(l, Id.mk_name(Id.SomeString n)), valts l lsym va), Ext.LF.Nil)
    
    | VAltFn(l1, VName(n1), VLa([va1]), vao) -> output_string out_channel n1; output_string out_channel " valts valtfn\n"; (**assuming only 1 element in list *)
                                                (begin match vao with
                                                   | None -> Ext.LF.App(l, Ext.LF.Root(l1, Ext.LF.Name(l1, Id.mk_name(Id.SomeString n1)), valts l1 lsym va1), Ext.LF.Nil)
                                                   | Some(VAltBin(l2, va)) -> output_string out_channel " valts valtfn valtbin else \n";
                                                                              Ext.LF.App(l, Ext.LF.Lam(l2, Id.mk_name(Id.SomeString n1), valtsPar l1 lsym va1), valts l1 lsym va)
                                                   | Some(a2) -> Ext.LF.App(l, Ext.LF.Root(l1, Ext.LF.Name(l1, Id.mk_name(Id.SomeString n1)), valts l1 lsym va1), valts l1 lsym a2)
                                                   (*| _ -> raise (Error ("getting closer to the problem")) *)
                                                 end)

    | VAltBin(l1,va) -> raise (Error ("Problem from valbin")) 

    | _ -> raise (Error ("Not implemented yet (in valts).")) 

(* function that deals with the list of premises *)

let rec judges' jn lsym lp l2 va =
   match lp with
     | [] -> Ext.LF.Atom(l2, Id.mk_name(Id.SomeString jn), valts l2 lsym va)
     | h::t -> let Premisse(l3, b1, c1, va1) = h in 
               Ext.LF.ArrTyp(l2, Ext.LF.Atom(l2, Id.mk_name(Id.SomeString jn), valts l3 lsym va1), judges' jn lsym t l2 va)

(* string list -> rule list -> Ext.Sgn.decl list *)
let rec judges jn lsym lr = 
   match lr with
    | [] -> []
    | h::t -> let Rule(l1, a, RName(s), Premisse(l2, b, c, va)) = h in let JName(s1) = jn in
              begin match a with
                | [] -> output_string out_channel  s; output_string out_channel " judges [] s s1 \n";  
                        let lv = [Ext.Sgn.Const(l1, Id.mk_name(Id.SomeString s), Ext.LF.Atom(l2, Id.mk_name(Id.SomeString s1), valts l2 lsym va))] in lv @ judges jn lsym t
                | la -> let lv = [Ext.Sgn.Const(l1, Id.mk_name(Id.SomeString s), judges' s1 lsym la l2 va)] in lv @ judges jn lsym t
              end

(* Theorems Section *)

let rec findJ va lju = 
  match va with
    | VAltAtomic(l, s, Some(vao)) -> let Jdef(s1, lsym) = findJu s lju in if (s1 = "") then findJ vao lju else (s1, lsym) (*raise (Error ("This theorem statement should refer to a judgment."))*)
    (*| VAltBin(l, va) ->
    | VAltLam(l, _, va) -> 
    | VAltFn(l, _, VLa([va1]), vao) ->
    | ValtPar(l,a,vao)*)

let stmt_to_prove l n st lju = 
  match st with 
    | ForAllExist (l1, tp, p) -> raise (Error ("Sorry, I am not implemented yet."))
    | Exist (l1, p) -> begin match p with
                          | Premisse( l2, None, None, va) -> output_string out_channel " stmttoprove n n\n";  let (jn, lsym) = findJ va lju in
                                                             Ext.Comp.TypBox(l1, Ext.LF.Atom(l1, Id.mk_name(Id.SomeString jn), valts l2 lsym va), Ext.LF.Null)
                          | Premisse _ -> raise (Error ("Sorry, i am not implemented yet."))
                        end 

let proofs l pl = 
  match pl with 
    | [] -> raise (Error ("Sorry, I am not implemented yet.[]"))
    | h::t -> 
  begin match h with
    | URule (l1, tp, RName(n), lvno) -> output_string out_channel " urule \n"; (** why do we ignore the tp *) Ext.LF.Root(l1, Ext.LF.Name( l1, Id.mk_name(Id.SomeString n)), Ext.LF.Nil)
    | Proof (l1, tp, VName(s), al) -> raise (Error ("Sorry, I am not implemented yet (Proof)."))
    | PRule (l1, tp, pf, lvn) -> raise (Error ("Sorry, I am not implemented yet (Prule)."))
    (*| Induction (l1, tp, VName(s), al) -> raise (Error ("Sorry, I am not implemented yet (Proof)."))*)
    | InductionHyp (l1) -> raise (Error ("Sorry, I am not implemented yet (IH)."))
    | CaseAn (l1, tp, lvn, al) -> raise (Error ("Sorry, I am not implemented yet (CaseAn)."))
    | PTheorem (l1, tn) -> raise (Error ("Sorry, I am not implemented yet (PTheorem)."))
    | _ -> raise (Error ("Error in theorem."))
  end

let theorem l n st pl lju = output_string out_channel " theorem translation \n"; let ctb =  stmt_to_prove l n st lju in let prf = proofs l pl in [Ext.Sgn.Rec(l, [Ext.Comp.RecFun( Id.mk_name(Id.SomeString n), ctb, Ext.Comp.Box(l, [], prf))])]


(* string list -> string list -> Ext.Sgn.decl list, first list terminals secong types *)
let rec recSectionDecl lt ltyp ls lju = 
  match ls with 
    | [] -> []
    | h::t -> begin match h with
                | Grammar (_, lp) -> let ls = sgnTypes lt ltyp [lp] in output_string out_channel "Grammar decl \n"; (ls @ recSectionDecl lt ltyp t lju)
                | Judgement(l, jn, js, a, lr) -> output_string out_channel "Judgement \n"; output_string out_channel "print list in judgement \n";printL ltyp; 
                                                 let (l1, sgnj) = sgnJudge l jn js ltyp in let lj = judges jn l1 lr in let JName(s1)=jn in (*output_string out_channel "Print list of symbol in recSectionDecl: \n"; printL l1;*)
                                                                                           [sgnj] @ lj @ recSectionDecl lt ltyp t (Jdef(s1,l1)::lju)
                | Theorems (l, TName(n), st, pl) -> output_string out_channel "Theorems \n"; theorem l n st pl lju
              end

(* section list -> string list *)
let rec recSectionDeclGram l ls =
  match ls with
    | [] -> []
    | Grammar (_, Production(l1, Typ(l2, t1), la)):: t -> output_string out_channel t1; output_string out_channel " gram decl \n"; t1 :: recSectionDeclGram l t 
    | Judgement _ ::t -> recSectionDeclGram l t
    | Terminals_decl _:: t -> let s = locToString(l) in let s1 = s ^ "Should only have one declaration of terminals" in raise (Error (s1))
    | Theorems _ :: t-> recSectionDeclGram l t

(* string list -> string list -> Syntax.section list -> Syntax.Ext.Sgn.decl list *)
let sectionDecls ls = 
  match ls with
    | Terminals_decl(l,lt):: t -> let lt1 = makeTerminals lt in let ltyp = recSectionDeclGram l t in output_string out_channel "Section Decls \n"; 
                                  printL ltyp; recSectionDecl lt1 ltyp t []
    | _ -> raise (Error ("No terminal declaration or grammar at the beginnig of file"))