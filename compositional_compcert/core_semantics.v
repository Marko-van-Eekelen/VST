Load loadpath.

(*CompCert imports*)
Require Import Events.
Require Import Memory.
Require Import Coqlib.
Require Import Values.
Require Import Maps.
Require Import Integers.
Require Import AST.
Require Import Globalenvs.

Require Import msl.Axioms.
Require Import compositional_compcert.mem_lemmas.

(** A "core semantics represents" a fairly traditional, sequential,
   small step semantics of computation.  They are designed to
   cooperate with "extensions" which give semantics to primtive
   constructs not defined by the extensible semantics (e.g., external
   function calls).

   The [G] type parameter is the type of global environments, the type
   [C] is the type of core states, and the type [E] is the type of
   extension requests.  The [at_external] function gives a way to
   determine when the sequential execution is blocked on an extension
   call, and to extract the data necessary to execute the call.
   [after_external] give a way to inject the extension call results
   back into the sequential state so execution can continue.  The type
   parameter [D] stands for the type of initialization data, eg list
   (ident * globvar V).

   [make_initial_core] produces the core state corresponding
   to an entry point of the program/module.  The arguments are the
   program's genv, a pointer to the function to run, and
   the arguments for that function.

   The [safely_halted] predicate indicates when a program state
   has reached a halted state, and what it's exit code/return value is
   when it has reached such a state.

   [corestep] is the fundamental small-step relation for
   the sequential semantics.

   The remaining properties give basic sanity properties which constrain
   the behavior of programs.
    1) a state cannot be both blocked on an extension call
        and also step,
    2) a state cannot both step and be halted
    3) a state cannot both be halted and blocked on an external call
    4) after external calls, cores are back in a "runnable" state
       (NOTE: this axiom may be removed at some point) *)

Record CoreSemantics {G C M D:Type}: Type :=
  { initial_mem: G -> M -> D -> Prop;
    make_initial_core : G -> val -> list val -> option C;
    at_external : C -> option (external_function * signature * list val);
    after_external : option val -> C -> option C;
    safely_halted : C -> option val; 
    corestep : G -> C -> M -> C -> M -> Prop;

    corestep_not_at_external: forall ge m q m' q', 
      corestep ge q m q' m' -> at_external q = None;
    corestep_not_halted: forall ge m q m' q', 
      corestep ge q m q' m' -> safely_halted q = None;
    at_external_halted_excl: forall q, 
      at_external q = None \/ safely_halted q = None;
    after_at_external_excl : forall retv q q',
      after_external retv q = Some q' -> at_external q' = None
  }.

Implicit Arguments CoreSemantics [].

(**  Multistepping *)

Section corestepN.
  Context {G C M E D:Type} (Sem:CoreSemantics G C M D) (ge:G).

  Fixpoint corestepN (n:nat) : C -> M -> C -> M -> Prop :=
    match n with
      | O => fun c m c' m' => (c,m) = (c',m')
      | S k => fun c1 m1 c3 m3 => exists c2, exists m2,
        corestep Sem ge c1 m1 c2 m2 /\
        corestepN k c2 m2 c3 m3
    end.

  Lemma corestepN_add : forall n m c1 m1 c3 m3,
    corestepN (n+m) c1 m1 c3 m3 <->
    exists c2, exists m2,
      corestepN n c1 m1 c2 m2 /\
      corestepN m c2 m2 c3 m3.
  Proof.
    induction n; simpl; intuition.
    firstorder. firstorder.
    inv H. auto.
    decompose [ex and] H. clear H.
    destruct (IHn m x x0 c3 m3).
    apply H in H2. 
    decompose [ex and] H2. clear H2.
    repeat econstructor; eauto.
    decompose [ex and] H. clear H.
    exists x1. exists x2; split; auto.
    destruct (IHn m x1 x2 c3 m3). 
    eauto.
  Qed.

  Definition corestep_plus c m c' m' :=
    exists n, corestepN (S n) c m c' m'.

  Definition corestep_star c m c' m' :=
    exists n, corestepN n c m c' m'.

  Lemma corestep_plus_star : forall c1 c2 m1 m2,
    corestep_plus c1 m1 c2 m2 -> corestep_star c1 m1 c2 m2.
  Proof. intros. destruct H as [n1 H1]. eexists. apply H1. Qed.

  Lemma corestep_plus_trans : forall c1 c2 c3 m1 m2 m3,
    corestep_plus c1 m1 c2 m2 -> corestep_plus c2 m2 c3 m3 -> 
    corestep_plus c1 m1 c3 m3.
  Proof. intros. destruct H as [n1 H1]. destruct H0 as [n2 H2].
    destruct (corestepN_add (S n1) (S n2) c1 m1 c3 m3) as [_ H].
    eexists. apply H. exists c2. exists m2. split; assumption.
  Qed.

  Lemma corestep_star_plus_trans : forall c1 c2 c3 m1 m2 m3,
    corestep_star c1 m1 c2 m2 -> corestep_plus c2 m2 c3 m3 -> 
    corestep_plus c1 m1 c3 m3.
  Proof. intros. destruct H as [n1 H1]. destruct H0 as [n2 H2].
    destruct (corestepN_add n1 (S n2) c1 m1 c3 m3) as [_ H]. 
    rewrite <- plus_n_Sm in H.
    eexists. apply H.  exists c2. exists m2.  split; assumption.
  Qed.

  Lemma corestep_plus_star_trans: forall c1 c2 c3 m1 m2 m3,
    corestep_plus c1 m1 c2 m2 -> corestep_star c2 m2 c3 m3 -> 
    corestep_plus c1 m1 c3 m3.
  Proof. intros. destruct H as [n1 H1]. destruct H0 as [n2 H2].
    destruct (corestepN_add (S n1) n2 c1 m1 c3 m3) as [_ H]. 
    rewrite plus_Sn_m in H.
    eexists. apply H.  exists c2. exists m2.  split; assumption.
  Qed.

  Lemma corestep_star_trans: forall c1 c2 c3 m1 m2 m3, 
    corestep_star c1 m1 c2 m2 -> corestep_star c2 m2 c3 m3 -> 
    corestep_star c1 m1 c3 m3.
  Proof. intros. destruct H as [n1 H1]. destruct H0 as [n2 H2].
    destruct (corestepN_add n1 n2 c1 m1 c3 m3) as [_ H]. 
    eexists. apply H.  exists c2. exists m2.  split; assumption.
  Qed.

  Lemma corestep_plus_one: forall c m c' m',
    corestep  Sem ge c m c' m' -> corestep_plus c m c' m'.
  Proof. intros. unfold corestep_plus, corestepN. simpl.
    exists O. exists c'. exists m'. eauto. 
  Qed.

  Lemma corestep_plus_two: forall c m c' m' c'' m'',
    corestep  Sem ge c m c' m' -> corestep  Sem ge c' m' c'' m'' -> 
    corestep_plus c m c'' m''.
  Proof. intros. 
    exists (S O). exists c'. exists m'. split; trivial. 
    exists c''. exists m''. split; trivial. reflexivity.
  Qed.

  Lemma corestep_star_zero: forall c m, corestep_star  c m c m.
  Proof. intros. exists O. reflexivity. Qed.

  Lemma corestep_star_one: forall c m c' m',
    corestep  Sem ge c m c' m' -> corestep_star c m c' m'.
  Proof. intros. 
    exists (S O). exists c'. exists m'. split; trivial. reflexivity. 
  Qed.

  Lemma corestep_plus_split: forall c m c' m',
    corestep_plus c m c' m' ->
    exists c'', exists m'', corestep  Sem ge c m c'' m'' /\ 
      corestep_star c'' m'' c' m'.
  Proof. intros.
    destruct H as [n [c2 [m2 [Hstep Hstar]]]]. simpl in*. 
    exists c2. exists m2. split. assumption. exists n. assumption.  
  Qed.

End corestepN.

(** "Cooperating" semantics impose additional constraints; in particular, 
   they require that the memories produced by coresteps contain no dangling 
   pointers. *)

Record CoopCoreSem {G C D} :=
  { coopsem :> CoreSemantics G C mem D;
    corestep_fwd : forall g c m c' m' (CS: corestep coopsem g c m c' m'), 
      mem_forward m m';
    corestep_wdmem: forall g c m c' m' (CS: corestep coopsem g c m c' m'), 
      mem_wd m -> mem_wd m';
    initmem_wd: forall g m d, initial_mem coopsem g m d -> mem_wd m }.

Implicit Arguments CoopCoreSem [].

Lemma inject_separated_incr_fwd: 
  forall j j' m1 m2 j'' m2'
    (InjSep : inject_separated j j' m1 m2)
    (InjSep' : inject_separated j' j'' m1 m2')
    (InjIncr' : inject_incr j' j'')
    (Fwd: mem_forward m2 m2'),
    inject_separated j j'' m1 m2.
Proof.
intros. intros b. intros. remember (j' b) as z. 
destruct z; apply eq_sym in Heqz.
destruct p. specialize (InjIncr' _ _ _ Heqz). 
rewrite InjIncr' in H0. inv H0.
apply (InjSep _ _ _ H Heqz). 
destruct (InjSep' _ _ _ Heqz H0).
split. trivial.
intros N. apply H2. eapply Fwd. apply N.
Qed.

Lemma external_call_mem_forward:
  forall (ef : external_function) (F V : Type) (ge : Genv.t F V)
    (vargs : list val) (m1 : mem) (t : trace) (vres : val) (m2 : mem),
    external_call ef ge vargs m1 t vres m2 -> mem_forward m1 m2.
Proof.
intros.
intros b Hb.
split; intros. eapply external_call_valid_block; eauto.
eapply external_call_max_perm; eauto.
Qed.

(** Rely-Guarantee core semantics extend coop core semantics with a predicate 
   tracking blocks "private" to this core.  Inuitively, private blocks are 
   blocks allocated by coresteps of this semantics. *)

Record RelyGuaranteeSemantics {G C D} :=
  { csem :> CoreSemantics G C mem D;
    private_block: C -> block -> Prop;
    private_dec: forall c b, 
      {private_block c b}+{~private_block c b};
    private_initial: forall ge v vs c,
      make_initial_core csem ge v vs = Some c -> 
      forall b, ~private_block c b;
    private_step: forall ge c m c' m',
      corestep csem ge c m c' m' -> 
      (forall b, private_block c' b <-> 
        private_block c b \/ Mem.nextblock m <= b < Mem.nextblock m');
    private_external: forall c c' retv,
      after_external csem retv c = Some c' -> 
      (forall b, private_block c' b <-> private_block c b) }.

Implicit Arguments RelyGuaranteeSemantics [].

Section RelyGuaranteeSemanticsLemmas.
Context {G C D: Type}.
Variable rgsem: RelyGuaranteeSemantics G C D.

Lemma private_corestep: forall ge c m c' m' b,
  private_block rgsem c b -> 
  corestep rgsem ge c m c' m' -> 
  private_block rgsem c' b.
Proof.
intros until b; intros H1 H2.
solve[erewrite private_step; eauto].
Qed.

Lemma private_corestepN: forall ge n c m c' m' b,
  private_block rgsem c b -> 
  corestepN rgsem ge n c m c' m' -> 
  private_block rgsem c' b.
Proof.
intros until b; revert c m; induction n; simpl.
solve[intros ? ? ? X; inv X; auto].
intros until m; intros H1 [c2 [m2 [H2 H3]]].
eapply private_corestep in H2; eauto.
Qed.

Lemma private_new: forall ge c m c' m' b,
  ~private_block rgsem c b -> 
  corestep rgsem ge c m c' m' -> 
  (private_block rgsem c' b <-> Mem.nextblock m <= b < Mem.nextblock m').
Proof.
intros until b; intros H1 H2; split; intros H3.
rewrite private_step in H3; eauto.
destruct H3; auto.
elimtype False; auto.
rewrite private_step; eauto.
Qed.

Lemma private_newN: forall ge n c m c' m' b,
  ~private_block rgsem c b -> 
  corestepN rgsem ge n c m c' m' -> 
  (private_block rgsem c' b <-> Mem.nextblock m <= b < Mem.nextblock m').
Proof.
intros until b; revert c m; induction n; auto.
(*solve[intros ? ? ? X; inv X; intros; elimtype False; auto].
simpl; intros until m; intros H1 [c2 [m2 [H2 H3]]] H4.
destruct (Z_le_dec (Mem.nextblock m) b).
destruct (Z_lt_dec b (Mem.nextblock m2)).
assert (H5: private_block rgsem c2 b).
 erewrite private_step.
 right; split; eauto.
 eapply H2.
eapply private_new with (ge := ge) (c' := c2) (m' := m2) in H1; eauto.
assert (Mem.nextblock m2 <= Mem.nextblock m').
 admit. (*TODO: requires coopsem*)
split; auto.
omega.
assert (Mem.nextblock m2 <= b) by omega.*)
Admitted. (*TODO*)

End RelyGuaranteeSemanticsLemmas.

Definition blockmap := block -> bool.

Section RelyGuaranteeSemanticsFunctor.
Context {G C D: Type}.
Variable csem: CoreSemantics G C mem D.

Definition rg_step (ge: G) (x: blockmap*C) (m: mem) (x': blockmap*C) (m': mem) :=
  match x, x' with (f, c), (f', c') => 
    corestep csem ge c m c' m' /\
    (forall b, f' b=true <-> f b=true \/ Mem.nextblock m <= b < Mem.nextblock m')
  end.

Program Definition RelyGuaranteeCoreSem: CoreSemantics G (blockmap*C) mem D :=
  Build_CoreSemantics G (blockmap*C) mem D 
    (*initial mem*)
    (initial_mem csem)
    (*make_initial_core*)
    (fun ge v vs => match make_initial_core csem ge v vs with
                    | Some c => Some (fun _ => false, c)
                    | None => None
                    end)
    (*at_external*)
    (fun x => at_external csem (snd x))
    (*after_external*)
    (fun retv x => match after_external csem retv (snd x) with
                   | Some c => Some (fst x, c)
                   | None => None
                   end)
    (*safely_halted*)
    (fun x => safely_halted csem (snd x))
    (*corestep*)
    rg_step
    _ _ _ _.
Next Obligation.
destruct H as [H1 H2]; apply corestep_not_at_external in H1; auto.
Qed.
Next Obligation.
destruct H as [H1 H2]; apply corestep_not_halted in H1; auto.
Qed.
Next Obligation. apply (at_external_halted_excl csem c). Qed.
Next Obligation. 
simpl in H.
case_eq (after_external csem retv c0); intros. 
rewrite H0 in H; inv H.
apply after_at_external_excl in H0; auto.
rewrite H0 in H; congruence.
Qed.

Program Definition RGSemantics: RelyGuaranteeSemantics G (blockmap*C) D :=
  Build_RelyGuaranteeSemantics G (blockmap*C) D
   RelyGuaranteeCoreSem
   (fun x b => fst x b = true) _ _ _ _.
Next Obligation.
simpl.
destruct (b0 b).
left; auto.
right; auto.
Qed.
Next Obligation. 
simpl.
destruct (make_initial_core csem ge v vs).
inv H; auto.
congruence.
Qed.
Next Obligation. destruct H; auto. Qed.
Next Obligation. 
simpl in *|-*; destruct (after_external csem retv c); try solve[congruence].
solve[inv H; split; auto].
Qed.

End RelyGuaranteeSemanticsFunctor.