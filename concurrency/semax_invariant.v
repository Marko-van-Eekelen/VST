Require Import Coq.Strings.String.

Require Import compcert.lib.Integers.
Require Import compcert.common.AST.
Require Import compcert.cfrontend.Clight.
Require Import compcert.common.Globalenvs.
Require Import compcert.common.Memory.
Require Import compcert.common.Memdata.
Require Import compcert.common.Values.

Require Import msl.Coqlib2.
Require Import msl.eq_dec.
Require Import msl.seplog.
Require Import veric.initial_world.
Require Import veric.juicy_mem.
Require Import veric.juicy_mem_lemmas.
Require Import veric.semax_prog.
Require Import veric.compcert_rmaps.
Require Import veric.Clight_new.
Require Import veric.Clightnew_coop.
Require Import veric.semax.
Require Import veric.semax_ext.
Require Import veric.juicy_extspec.
Require Import veric.initial_world.
Require Import veric.juicy_extspec.
Require Import veric.tycontext.
Require Import veric.semax_ext.
Require Import veric.semax_ext_oracle.
Require Import veric.res_predicates.
Require Import veric.mem_lessdef.
Require Import floyd.coqlib3.
Require Import sepcomp.semantics.
Require Import sepcomp.step_lemmas.
Require Import sepcomp.event_semantics.
Require Import concurrency.coqlib5.
Require Import concurrency.semax_conc.
Require Import concurrency.juicy_machine.
Require Import concurrency.concurrent_machine.
Require Import concurrency.scheduler.
Require Import concurrency.addressFiniteMap.
Require Import concurrency.permissions.
Require Import concurrency.JuicyMachineModule.
Require Import concurrency.age_to.
Require Import concurrency.sync_preds_defs.
Require Import concurrency.join_lemmas.

(*! Instantiation of modules *)
Export THE_JUICY_MACHINE.
Export JSEM.
Module Machine :=THE_JUICY_MACHINE.JTP.
Definition schedule := SCH.schedule.
Export JuicyMachineLemmas.
Export ThreadPool.

Set Bullet Behavior "Strict Subproofs".

Ltac cleanup :=
  unfold lockRes in *;
  unfold LocksAndResources.lock_info in *;
  unfold LocksAndResources.res in *;
  unfold lockGuts in *.

Ltac join_level_tac :=
  try
    match goal with
      cnti : containsThread ?tp _,
             compat : mem_compatible_with ?tp ?m ?Phi |- _ =>
      assert (join_sub (getThreadR cnti) Phi) by (apply compatible_threadRes_sub, compat)
    end;
  repeat match goal with H : join_sub _ _ |- _ => apply join_sub_level in H end;
  repeat match goal with H : join _ _ _ |- _ => apply join_level in H; destruct H end;
  cleanup;
  try congruence.

(*+ Description of the invariant *)

Definition cm_state := (Mem.mem * Clight.genv * (schedule * Machine.t))%type.

Inductive state_step : cm_state -> cm_state -> Prop :=
| state_step_empty_sched ge m jstate :
    state_step
      (m, ge, (nil, jstate))
      (m, ge, (nil, jstate))
| state_step_c ge m m' sch sch' jstate jstate' :
    @JuicyMachine.machine_step ge sch nil jstate m sch' nil jstate' m' ->
    state_step
      (m, ge, (sch, jstate))
      (m', ge, (sch', jstate')).


(*! Coherence between locks in dry/wet memories and lock pool *)

Inductive cohere_res_lock : forall (resv : option (option rmap)) (wetv : resource) (dryv : memval), Prop :=
| cohere_notlock wetv dryv:
    (forall sh sh' z P, wetv <> YES sh sh' (LK z) P) ->
    cohere_res_lock None wetv dryv
| cohere_locked R wetv :
    islock_pred R wetv ->
    cohere_res_lock (Some None) wetv (Byte (Integers.Byte.zero))
| cohere_unlocked R phi wetv :
    islock_pred R wetv ->
    R phi ->
    cohere_res_lock (Some (Some phi)) wetv (Byte (Integers.Byte.one)).

Definition load_at m loc := Mem.load Mint32 m (fst loc) (snd loc).

Definition lock_coherence (lset : AMap.t (option rmap)) (phi : rmap) (m : mem) : Prop :=
  forall loc : address,
    match AMap.find loc lset with
    
    (* not a lock *)
    | None => ~isLK (phi @ loc) /\ ~isCT (phi @ loc)
    
    (* locked lock *)
    | Some None =>
      load_at m loc = Some (Vint Int.zero) /\
      exists sh R, LK_at R sh loc phi
    
    (* unlocked lock *)
    | Some (Some lockphi) =>
      load_at m loc = Some (Vint Int.one) /\
      exists sh (R : mpred),
        LK_at R sh loc phi /\
        (app_pred R (age_by 1 lockphi) \/ level phi = O)
        (*/\
        match age1 lockphi with
        | Some p => app_pred R p
        | None => Logic.True
        end*)
    end.

Definition far (ofs1 ofs2 : Z) := (Z.abs (ofs1 - ofs2) >= 4)%Z.

Lemma far_range ofs ofs' z :
  (0 <= z < 4)%Z ->
  far ofs ofs' ->
  ~(ofs <= ofs' + z < ofs + size_chunk Mint32)%Z.
Proof.
  unfold far; simpl.
  intros H1 H2.
  zify.
  omega.
Qed.

Definition lock_sparsity {A} (lset : AMap.t A) : Prop :=
  forall loc1 loc2,
    AMap.find loc1 lset <> None ->
    AMap.find loc2 lset <> None ->
    loc1 = loc2 \/
    fst loc1 <> fst loc2 \/
    (fst loc1 = fst loc2 /\ far (snd loc1) (snd loc2)).

Lemma lock_sparsity_age_to tp n :
  lock_sparsity (lset tp) -> 
  lock_sparsity (lset (age_tp_to n tp)).
Proof.
  destruct tp as [A B C lset0]; simpl.
  intros S l1 l2 E1 E2; apply (S l1 l2).
  - rewrite AMap_find_map_option_map in E1.
    cleanup.
    destruct (AMap.find (elt:=option rmap) l1 lset0); congruence || tauto.
  - rewrite AMap_find_map_option_map in E2.
    cleanup.
    destruct (AMap.find (elt:=option rmap) l2 lset0); congruence || tauto.
Qed.

Definition lset_same_support {A} (lset1 lset2 : AMap.t A) :=
  forall loc,
    AMap.find loc lset1 = None <->
    AMap.find loc lset2 = None.

Lemma sparsity_same_support {A} (lset1 lset2 : AMap.t A) :
  lset_same_support lset1 lset2 ->
  lock_sparsity lset1 ->
  lock_sparsity lset2.
Proof.
  intros same sparse l1 l2.
  specialize (sparse l1 l2).
  rewrite <-(same l1).
  rewrite <-(same l2).
  auto.
Qed.

Lemma same_support_change_lock {A} (lset : AMap.t A) l x :
  AMap.find l lset <> None ->
  lset_same_support lset (AMap.add l x lset).
Proof.
  intros E l'.
  rewrite AMap_find_add.
  if_tac.
  - split; congruence.
  - tauto.
Qed.

Lemma lset_same_support_map {A} m (f : A -> A) :
  lset_same_support (AMap.map (option_map f) m) m.
Proof.
  intros k.
  rewrite AMap_find_map_option_map.
  destruct (AMap.find (elt:=option A) k m); simpl; split; congruence.
Qed.

Lemma lset_same_support_sym {A} (m1 m2 : AMap.t A) :
  lset_same_support m1 m2 ->
  lset_same_support m2 m1.
Proof.
  unfold lset_same_support in *.
  intros E loc.
  rewrite E; tauto.
Qed.

Lemma lset_same_support_trans {A} (m1 m2 m3 : AMap.t A) :
  lset_same_support m1 m2 ->
  lset_same_support m2 m3 ->
  lset_same_support m1 m3.
Proof.
  unfold lset_same_support in *.
  intros E F loc.
  rewrite E; apply F.
Qed.

(*! Joinability and coherence *)

Lemma mem_compatible_forget {tp m phi} :
  mem_compatible_with tp m phi -> mem_compatible tp m.
Proof. intros M; exists phi. apply M. Qed.

Definition jm_
  {tp m PHI i}
  (cnti : Machine.containsThread tp i)
  (mcompat : mem_compatible_with tp m PHI)
  : juicy_mem :=
  personal_mem (thread_mem_compatible (mem_compatible_forget mcompat) cnti).

Lemma personal_mem_ext m phi phi' pr pr' :
  phi = phi' ->
  @personal_mem m phi pr =
  @personal_mem m phi' pr'.
Proof.
  intros <-; f_equal; apply proof_irr.
Qed.

(*! Invariant (= above properties + safety + uniqueness of Krun) *)

Definition threads_safety {Z} (Jspec : juicy_ext_spec Z) m ge tp PHI (mcompat : mem_compatible_with tp m PHI) n :=
  forall i (cnti : Machine.containsThread tp i) (ora : Z),
    match Machine.getThreadC cnti with
    | Krun c
    | Kblocked c => semax.jsafeN Jspec ge n ora c (jm_ cnti mcompat)
    | Kresume c v =>
      forall c',
        (* [v] is not used here. The problem is probably coming from
           the definition of JuicyMachine.resume_thread'. *)
        cl_after_external (Some (Vint Int.zero)) c = Some c' ->
        semax.jsafeN Jspec ge n ora c' (jm_ cnti mcompat)
    | Kinit _ _ => Logic.True
    end.

Definition threads_wellformed tp :=
  forall i (cnti : containsThread tp i),
    match getThreadC cnti with
    | Krun q => Logic.True
    | Kblocked q => cl_at_external q <> None
    | Kresume q v => cl_at_external q <> None /\ v = Vundef
    | Kinit _ _ => Logic.True
    end.

Definition unique_Krun tp sch :=
  (lt 1 tp.(num_threads).(pos.n) -> forall i cnti q,
      @getThreadC i tp cnti = Krun q ->
      exists sch', sch = i :: sch').

Definition no_Krun tp :=
  forall i cnti q, @getThreadC i tp cnti <> Krun q.

Lemma no_Krun_unique_Krun tp sch : no_Krun tp -> unique_Krun tp sch.
Proof.
  intros H _ i cnti q E; destruct (H i cnti q E).
Qed.

Lemma containsThread_age_tp_to_eq tp n :
  containsThread (age_tp_to n tp) = containsThread tp.
Proof.
  destruct tp; reflexivity.
Qed.

Lemma no_Krun_age_tp_to n tp :
  no_Krun (age_tp_to n tp) = no_Krun tp.
Proof.
  destruct tp; reflexivity.
Qed.

Lemma unique_Krun_age_tp_to n tp sch :
  unique_Krun (age_tp_to n tp) sch <-> unique_Krun tp sch.
Proof.
  destruct tp; reflexivity.
Qed.

Lemma no_Krun_stable tp i cnti c' phi' :
  (forall q, c' <> Krun q) ->
  no_Krun tp ->
  no_Krun (@updThread i tp cnti c' phi').
Proof.
  intros notkrun H j cntj q.
  destruct (eq_dec i j).
  - subst.
    rewrite gssThreadCode.
    apply notkrun.
  - unshelve erewrite gsoThreadCode; auto.
Qed.

Lemma no_Krun_unique_Krun_updThread tp i sch cnti q phi' :
  no_Krun tp ->
  unique_Krun (@updThread i tp cnti (Krun q) phi') (i :: sch).
Proof.
  intros NO H j cntj q'.
  destruct (eq_dec i j).
  - subst.
    rewrite gssThreadCode.
    injection 1 as <-. eauto.
  - Set Printing Implicit.
    unshelve erewrite gsoThreadCode; auto.
    intros E; specialize (NO _ _ _ E). destruct NO.
Qed.

Lemma no_Krun_updLockSet tp loc ophi :
  no_Krun tp ->
  no_Krun (updLockSet tp loc ophi).
Proof.
  intros N; apply N.
Qed.

Lemma ssr_leP_inv i n : is_true (ssrnat.leq i n) -> i <= n.
Proof.
  pose proof @ssrnat.leP i n as H.
  intros E; rewrite E in H.
  inversion H; auto.
Qed.

Lemma different_threads_means_several_threads i j tp
      (cnti : containsThread tp i)
      (cntj : containsThread tp j) :
  i <> j -> 1 < pos.n (num_threads tp).
Proof.
  unfold containsThread in *.
  simpl in *.
  unfold tid in *.
  destruct tp as [n].
  simpl in *.
  remember (pos.n n) as k; clear Heqk n.
  apply ssr_leP_inv in cnti.
  apply ssr_leP_inv in cntj.
  omega.
Qed.

Lemma unique_Krun_no_Krun tp i sch cnti :
  unique_Krun tp (i :: sch) ->
  (forall q : code, @getThreadC i tp cnti <> Krun q) ->
  no_Krun tp.
Proof.
  intros U N j cntj q E.
  assert (i <> j). {
    intros <-.
    apply N with q.
    exact_eq E; do 2 f_equal.
    apply proof_irr.
  }
  unfold unique_Krun in *.
  assert_specialize U.
  now eapply (different_threads_means_several_threads i j); eauto.
  specialize (U _ _ _ E). destruct U. congruence.
Qed.

Lemma unique_Krun_no_Krun_updThread tp i sch cnti c' phi' :
  (forall q, c' <> Krun q) ->
  unique_Krun tp (i :: sch) ->
  no_Krun (@updThread i tp cnti c' phi').
Proof.
  intros notkrun uniq j cntj q.
  destruct (eq_dec i j) as [<-|N].
  - rewrite gssThreadCode.
    apply notkrun.
  - unshelve erewrite gsoThreadCode; auto.
    unfold unique_Krun in *.
    assert_specialize uniq.
    now eapply (different_threads_means_several_threads i j); eauto.
    intros E.
    specialize (uniq _ _ _ E).
    destruct uniq.
    congruence.
Qed.

Definition matchfunspec (ge : genviron) Gamma : forall Phi, Prop :=
  (ALL b : block,
    (ALL fs : funspec,
      seplog.func_at' fs (b, 0%Z) -->
      (EX id : ident,
        !! (ge id = Some b) && !! (Gamma ! id = Some fs))))%pred.

Definition lock_coherence' tp PHI m (mcompat : mem_compatible_with tp m PHI) :=
  lock_coherence
    (lset tp) PHI
    (restrPermMap
       (mem_compatible_locks_ltwritable
          (mem_compatible_forget mcompat))).

Inductive state_invariant {Z} (Jspec : juicy_ext_spec Z) Gamma (n : nat) : cm_state -> Prop :=
  | state_invariant_c
      (m : mem) (ge : genv) (sch : schedule) (tp : ThreadPool.t) (PHI : rmap)
      (lev : level PHI = n)
      (gamma : matchfunspec (filter_genv ge) Gamma PHI)
      (mcompat : mem_compatible_with tp m PHI)
      (lock_sparse : lock_sparsity (lset tp))
      (lock_coh : lock_coherence' tp PHI m mcompat)
      (safety : threads_safety Jspec m ge tp PHI mcompat n)
      (wellformed : threads_wellformed tp)
      (uniqkrun :  unique_Krun tp sch)
    : state_invariant Jspec Gamma n (m, ge, (sch, tp)).

(* Schedule irrelevance of the invariant *)
Lemma state_invariant_sch_irr {Z} (Jspec : juicy_ext_spec Z) Gamma n m ge i sch sch' tp :
  state_invariant Jspec Gamma n (m, ge, (i :: sch, tp)) ->
  state_invariant Jspec Gamma n (m, ge, (i :: sch', tp)).
Proof.
  intros INV.
  inversion INV as [m0 ge0 sch0 tp0 PHI lev gam compat sparse lock_coh safety wellformed uniqkrun H0];
    subst m0 ge0 sch0 tp0.
  refine (state_invariant_c Jspec Gamma n m ge (i :: sch') tp PHI lev gam compat sparse lock_coh safety wellformed _).
  clear -uniqkrun.
  intros H i0 cnti q H0.
  destruct (uniqkrun H i0 cnti q H0) as [sch'' E].
  injection E as <- <-.
  eauto.
Qed.

Ltac absurd_ext_link_naming :=
  exfalso;
  match goal with
  | H : Some ((_ : string -> ident) _) = _ |- _ =>
    rewrite <-H in *
  end;
  match goal with
  | H : Some ((?ext_link : string -> ident) ?a) <> Some (?ext_link ?a) |- _ =>
    congruence
  | H : Some ((?ext_link : string -> ident) ?a) = Some (?ext_link ?b) |- _ =>
    match goal with
    | ext_link_inj : forall s1 s2, ext_link s1 = ext_link s2 -> s1 = s2 |- _ =>
      assert (a = b) by (apply ext_link_inj; congruence); congruence
    end
  end.

Ltac funspec_destruct s :=
  simpl (ext_spec_pre _); simpl (ext_spec_type _); simpl (ext_spec_post _);
  unfold funspec2pre, funspec2post;
  let Heq_name := fresh "Heq_name" in
  destruct (oi_eq_dec (Some (_ s)) (ef_id _ (EF_external _ _)))
    as [Heq_name | Heq_name]; try absurd_ext_link_naming.



(* if a hypothesis if of the form forall a1 a2 a3 a4 ...,
"forall_bringvar 3" will move a3 as the first variable, i.e. forall a3
a1 a2 a4..., assuming the operation is legal wrt dependent types *)

(* This allows us to define "specialize H _ _ _ term" below *)

Tactic Notation "forall_bringvar" "2" hyp(H) :=
  match type of H with
    (forall a : ?A, forall b : ?B, ?P) =>
    let H' := fresh "H" in
    assert (H' : forall b : B, forall a : A, P)
      by (intros; eapply H; eauto);
    move H' after H;
    clear H; rename H' into H
  end.

Tactic Notation "forall_bringvar" "2" hyp(H) :=
  match type of H with
    (forall a : ?A, forall b : ?B, ?P) =>
    let H' := fresh "H" in
    assert (H' : forall b : B, forall a : A, P)
      by (intros; eapply H; eauto);
    move H' after H;
    clear H; rename H' into H
  end.

Tactic Notation "forall_bringvar" "3" hyp(H) :=
  match type of H with
    (forall a : ?A, forall b : ?B, forall c : ?C, ?P) =>
    let H' := fresh "H" in
    assert (H' : forall c : C, forall a : A, forall b : B, P)
      by (intros; eapply H; eauto);
    move H' after H;
    clear H; rename H' into H
  end.

Tactic Notation "forall_bringvar" "4" hyp(H) :=
  match type of H with
    (forall a : ?A, forall b : ?B, forall c : ?C, forall d : ?D, ?P) =>
    let H' := fresh "H" in
    assert (H' : forall d : D, forall a : A, forall b : B, forall c : C, P)
      by (intros; eapply H; eauto);
    move H' after H;
    clear H; rename H' into H
  end.

Tactic Notation "forall_bringvar" "5" hyp(H) :=
  match type of H with
    (forall a : ?A, forall b : ?B, forall c : ?C, forall d : ?D, forall e : ?E, ?P) =>
    let H' := fresh "H" in
    assert (H' :  forall e : E, forall a : A, forall b : B, forall c : C, forall d : D, P)
      by (intros; eapply H; eauto);
    move H' after H;
    clear H; rename H' into H
  end.

Tactic Notation "forall_bringvar" "6" hyp(H) :=
  match type of H with
    (forall a : ?A, forall b : ?B, forall c : ?C, forall d : ?D, forall e : ?E, forall f : ?F, ?P) =>
    let H' := fresh "H" in
    assert (H' :  forall f : F, forall a : A, forall b : B, forall c : C, forall d : D, forall e : E, P)
      by (intros; eapply H; eauto);
    move H' after H;
    clear H; rename H' into H
  end.

Tactic Notation "specialize" hyp(H) "_" constr(t) :=
  forall_bringvar 2 H; specialize (H t).

Tactic Notation "specialize" hyp(H) "_" "_" constr(t) :=
  forall_bringvar 3 H; specialize (H t).

Tactic Notation "specialize" hyp(H) "_" "_" "_" constr(t) :=
  forall_bringvar 4 H; specialize (H t).

Tactic Notation "specialize" hyp(H) "_" "_" "_" "_" constr(t) :=
  forall_bringvar 5 H; specialize (H t).

Tactic Notation "specialize" hyp(H) "_" "_" "_" "_" "_" constr(t) :=
  forall_bringvar 6 H; specialize (H t).
