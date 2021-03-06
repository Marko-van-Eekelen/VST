Require Import progs.verif_incr.
Require Import progs.verif_cond.
Require Import msl.predicates_sl.
Require Import floyd.proofauto.
Require Import concurrency.semax_conc.
Require Import progs.cond_queue.

Instance CompSpecs : compspecs. make_compspecs prog. Defined.
Definition Vprog : varspecs. mk_varspecs prog. Defined.

Definition acquire_spec := DECLARE _acquire acquire_spec.
Definition release_spec := DECLARE _release release_spec.
Definition makelock_spec := DECLARE _makelock (makelock_spec _).
(*Definition freelock_spec := DECLARE _freelock (freelock_spec _).*)
Definition spawn_spec := DECLARE _spawn_thread spawn_spec.
(*Definition freelock2_spec := DECLARE _freelock2 (freelock2_spec _).
Definition release2_spec := DECLARE _release2 release2_spec.*)
Definition makecond_spec := DECLARE _makecond (makecond_spec _).
(*Definition freecond_spec := DECLARE _freecond (freecond_spec _).*)
Definition wait_spec := DECLARE _wait (wait_spec _).
Definition signal_spec := DECLARE _signal (signal_spec _).

Definition malloc_spec :=
 DECLARE _malloc
  WITH n: Z
  PRE [ 1%positive OF tuint ]
     PROP (4 <= n <= Int.max_unsigned) 
     LOCAL (temp 1%positive (Vint (Int.repr n)))
     SEP ()
  POST [ tptr tvoid ] 
     EX v: val,
     PROP (malloc_compatible n v) 
     LOCAL (temp ret_temp v) 
     SEP (memory_block Tsh n v).

Definition free_spec :=
 DECLARE _free
  WITH p : val , n : Z
  PRE [ 1%positive OF tptr tvoid ]  
     (* we should also require natural_align_compatible (eval_id 1) *)
      PROP() LOCAL (temp 1%positive p)
      SEP (memory_block Tsh n p)
  POST [ tvoid ]
    PROP () LOCAL () SEP ().

Definition trequest := Tstruct _request_t noattr.

Definition process_spec :=
 DECLARE _process
  WITH _ : unit
  PRE [ _data OF tint ] PROP () LOCAL () SEP ()
  POST [ tvoid ] PROP () LOCAL () SEP ().

Definition get_request_spec :=
 DECLARE _get_request
  WITH _ : unit
  PRE [ ] PROP () LOCAL () SEP ()
  POST [ tptr trequest ]
    EX v : val, EX data : Z, PROP () LOCAL (temp ret_temp v)
      SEP (data_at Tsh trequest (Vint (Int.repr data)) v).

Definition process_request_spec :=
 DECLARE _process_request
  WITH request : val, data : Z
  PRE [ _request OF (tptr trequest) ]
     PROP ()
     LOCAL (temp _request request)
     SEP (data_at Tsh trequest (Vint (Int.repr data)) request)
  POST [ tvoid ]
    PROP () LOCAL () SEP (emp).

Definition MAX : nat := 10.

Definition complete l := l ++ repeat (Vint (Int.repr 0)) (MAX - length l).

Definition add_spec :=
 DECLARE _add
  WITH request : val, buf : val, len : val, reqs : list val
  PRE [ _request OF (tptr trequest) ]
   PROP ((length reqs < MAX)%nat)
   LOCAL (temp _request request; gvar _buf buf; gvar _length len)
   SEP (data_at Ews (tarray (tptr trequest) (Z.of_nat MAX)) (complete reqs) buf;
        data_at Ews (tarray tint 1) [Vint (Int.repr (Zlength reqs))] len)
  POST [ tvoid ]
   PROP ()
   LOCAL ()
   SEP (data_at Ews (tarray (tptr trequest) (Z.of_nat MAX)) (complete (reqs ++ [request])) buf;
        data_at Ews (tarray tint 1) [Vint (Int.repr (Zlength reqs))] len).

Definition remove_spec :=
 DECLARE _remove
  WITH buf : val, len : val, reqs : list val, req : val
  PRE [ ]
   PROP ((length reqs < MAX)%nat; isptr req)
   LOCAL (gvar _buf buf; gvar _length len)
   SEP (data_at Ews (tarray (tptr trequest) (Z.of_nat MAX)) (complete (reqs ++ [req])) buf;
        data_at Ews (tarray tint 1) [Vint (Int.repr (Zlength reqs + 1))] len)
  POST [ tptr trequest ]
   PROP ()
   LOCAL (temp ret_temp req)
   SEP (data_at Ews (tarray (tptr trequest) (Z.of_nat MAX)) (complete reqs) buf;
        data_at Ews (tarray tint 1) [Vint (Int.repr (Zlength reqs + 1))] len).

Definition lock_pred buf len := Exp _ (fun reqs =>
  Pred_list (Data_at _ Ews (tarray (tptr trequest) (Z.of_nat MAX)) (complete reqs) buf ::
             Data_at _ Ews (tarray tint 1) [Vint (Int.repr (Zlength reqs))] len ::
             Pred_prop (Forall isptr reqs /\ (length reqs <= MAX)%nat) ::
             map (fun r => Exp _ (fun data => Data_at _ Tsh trequest (Vint (Int.repr data)) r)) reqs)).

Definition producer_spec :=
 DECLARE _producer
  WITH y : val, x : val * val * share * val * val * val
  PRE [ _arg OF (tptr tvoid) ]
    let '(buf, len, sh, lock, cprod, ccon) := x in
    PROP  ()
    LOCAL (temp _arg y; gvar _buf buf; gvar _length len;
           gvar _requests_lock lock; gvar _requests_producer cprod; gvar _requests_consumer ccon)
    SEP   ((!!readable_share sh && emp);
           lock_inv sh lock (Interp (lock_pred buf len)); cond_var sh cprod; cond_var sh ccon)
  POST [ tptr tvoid ] PROP () LOCAL () SEP (emp).

Definition consumer_spec :=
 DECLARE _consumer
  WITH y : val, x : val * val * share * val * val * val
  PRE [ _arg OF (tptr tvoid) ]
    let '(buf, len, sh, lock, cprod, ccon) := x in
    PROP  ()
    LOCAL (temp _arg y; gvar _buf buf; gvar _length len;
           gvar _requests_lock lock; gvar _requests_producer cprod; gvar _requests_consumer ccon)
    SEP   ((!!readable_share sh && emp);
           lock_inv sh lock (Interp (lock_pred buf len)); cond_var sh cprod; cond_var sh ccon)
  POST [ tptr tvoid ] PROP () LOCAL () SEP (emp).

Definition main_spec :=
 DECLARE _main
  WITH u : unit
  PRE  [] main_pre prog u
  POST [ tint ] main_post prog u.

Definition Gprog : funspecs := augment_funspecs prog [acquire_spec; release_spec; (*release2_spec;*) makelock_spec;
  (*freelock_spec; freelock2_spec;*) spawn_spec; makecond_spec; (*freecond_spec;*) wait_spec; signal_spec;
  malloc_spec; free_spec;
  process_spec; get_request_spec; process_request_spec; add_spec; remove_spec; producer_spec; consumer_spec;
  main_spec].

Lemma body_process : semax_body Vprog Gprog f_process process_spec.
Proof.
  start_function.
  forward.
Qed.

Lemma body_get_request : semax_body Vprog Gprog f_get_request get_request_spec.
Proof.
  start_function.
  forward_call (sizeof trequest).
  { simpl; computable. }
  Intro p.
  rewrite memory_block_isptr; normalize.
  rewrite memory_block_size_compatible; [normalize | simpl; computable].
  unfold malloc_compatible in H.
  destruct p; try contradiction; destruct H.
  rewrite memory_block_data_at_.
  forward.
  eapply semax_pre; [|apply semax_return].
  go_lower; normalize.
  unfold POSTCONDITION, abbreviate.
  unfold frame_ret_assert, function_body_ret_assert; simpl; normalize.
  unfold PROPx, LOCALx, SEPx, local; simpl; normalize.
  unfold liftx; simpl; unfold lift.
  Exists (Vptr b i0); Exists 1; normalize.
  unfold lift1; entailer'.
  { unfold field_compatible; simpl; repeat split; auto.
    unfold align_attr; simpl.
    eapply Zdivides_trans; eauto; unfold natural_alignment; exists 2; omega. }
Qed.

Lemma body_process_request : semax_body Vprog Gprog f_process_request process_request_spec.
Proof.
  start_function.
  forward.
  forward_call tt.
  forward_call (request, sizeof trequest).
  { subst Frame; instantiate (1 := []); normalize.
    apply data_at_memory_block. }
  forward.
Qed.

Lemma upd_complete : forall l x, (length l < MAX)%nat -> 
  upd_Znth (Zlength l) (complete l) x = complete (l ++ [x]).
Proof.
  intros; unfold complete.
  rewrite upd_Znth_app2, Zminus_diag.
  rewrite app_length; simpl plus.
  destruct (MAX - length l)%nat eqn: Hminus; [omega|].
  replace (MAX - (length l + 1))%nat with n by omega.
  unfold upd_Znth, sublist.sublist; simpl.
  rewrite Zlength_cons.
  unfold Z.succ; rewrite Z.add_simpl_r.
  rewrite Zlength_correct, Nat2Z.id, firstn_exact_length.
  rewrite <- app_assoc; auto.
  { repeat rewrite Zlength_correct; omega. }
Qed.

Lemma body_add : semax_body Vprog Gprog f_add add_spec.
Proof.
  start_function.
  forward.
  unfold Znth; simpl.
  forward.
  { unfold MAX in *; entailer!; rewrite Zlength_correct; omega. }
  forward.
  cancel.
  rewrite upd_complete; auto.
Qed.

Lemma Znth_complete : forall n l d, n < Zlength l -> Znth n (complete l) d = Znth n l d.
Proof.
  intros; apply app_Znth1; auto.
Qed.

Lemma remove_complete : forall l x, (length l < MAX)%nat -> 
  upd_Znth (Zlength l) (complete (l ++ [x])) (Vint (Int.repr 0)) = complete l.
Proof.
  intros; unfold complete.
  rewrite upd_Znth_app1; [|repeat rewrite Zlength_correct; rewrite app_length; simpl; Omega0].
  rewrite app_length; simpl plus.
  rewrite upd_Znth_app2, Zminus_diag; [|rewrite Zlength_cons; simpl; omega].
  unfold upd_Znth, sublist.sublist.
  rewrite Zminus_diag; simpl firstn.
  destruct (MAX - length l)%nat eqn: Hminus; [omega|].
  replace (MAX - (length l + 1))%nat with n by omega.
  simpl.
  rewrite <- app_assoc; auto.
Qed.

Lemma body_remove : semax_body Vprog Gprog f_remove remove_spec.
Proof.
  start_function.
  forward.
  assert (0 <= Zlength reqs + 1 - 1 < 10).
  { rewrite Z.add_simpl_r, Zlength_correct; unfold MAX in *; omega. }
  assert (Znth (Zlength reqs + 1 - 1) (complete (reqs ++ [req])) Vundef = req) as Hnth.
  { rewrite Z.add_simpl_r, Znth_complete;
      [|repeat rewrite Zlength_correct; rewrite app_length; simpl; Omega0].
    rewrite app_Znth2, Zminus_diag; [auto | omega]. }
  forward.
  { entailer!.
    rewrite Hnth; auto. }
  forward.
  forward.
  cancel.
  rewrite Z.add_simpl_r, remove_complete; auto.
Qed.

Lemma Forall_app : forall A (P : A -> Prop) l1 l2,
  Forall P (l1 ++ l2) <-> Forall P l1 /\ Forall P l2.
Proof.
  induction l1; split; auto; intros.
  - destruct H; auto.
  - inversion H as [|??? H']; subst.
    rewrite IHl1 in H'; destruct H'; split; auto.
  - destruct H as (H & ?); inv H; constructor; auto.
    rewrite IHl1; split; auto.
Qed.

Lemma inv_precise : forall buf len (Hbuf : isptr buf) (Hlen : isptr len),
  precise (Interp (lock_pred buf len)).
Proof.
  simpl.
(*  intros; apply derives_precise with (Q := data_at_ Tsh (tarray (tptr trequest) 10) buf *
    data_at_ Tsh (tarray tint 1) len * fold_right sepcon emp (map (data_at_ Tsh trequest) ).
       (map Interp
          (map (fun r : val => Exp Z (fun data : Z => Data_at CompSpecs Tsh trequest (Vint (Int.repr data)) r)) x))))).
  - intros ? (? & a1 & a2 & ? & Ha1 & ? & b & Hjoinb & Ha2 & Hemp).
    assert (predicates_hered.app_pred emp b) as Hb.
    { destruct Hemp as (? & ? & Hjoinb' & ((? & ?) & Hemp) & ?); simpl in *.
      specialize (Hemp _ _ Hjoinb'); subst; auto. }
    apply sepalg.join_comm in Hjoinb.
    specialize (Hb _ _ Hjoinb); subst.
    exists a1, a2; split; [auto|].
    split; [apply (data_at_data_at_ _ _ _ _ _ Ha1) | apply (data_at_data_at_ _ _ _ _ _ Ha2)].
  - destruct buf, len; try contradiction.
    apply precise_sepcon; [|(*apply data_at_precise; auto*)admit].
    intros; unfold data_at_, field_at_, field_at, at_offset; simpl.
    apply precise_andp2.
    rewrite data_at_rec_eq; unfold withspacer, at_offset; simpl.
    unfold array_pred, aggregate_pred.array_pred; simpl.
    unfold Zlength, Znth; simpl.
    apply precise_andp2.
    rewrite data_at_rec_eq; simpl.
    repeat (apply precise_sepcon; [apply mapsto_undef_precise; auto|]).
    apply precise_emp.*)
Admitted.

Lemma inv_positive : forall buf len,
  positive_mpred (Interp (lock_pred buf len)).
Proof.
Admitted.

Lemma sepcon_app : forall l1 l2, fold_right sepcon emp (l1 ++ l2) =
  fold_right sepcon emp l1 * fold_right sepcon emp l2.
Proof.
  induction l1; simpl; intros.
  - rewrite emp_sepcon; auto.
  - rewrite IHl1, sepcon_assoc; auto.
Qed.

Lemma body_producer : semax_body Vprog Gprog f_producer producer_spec.
Proof.
  start_function.
  normalize.
  eapply semax_loop with (Q' := PROP ()
    LOCAL (temp _arg y; gvar _buf buf; gvar _length len; gvar _requests_lock lock;
           gvar _requests_producer cprod; gvar _requests_consumer ccon)
    SEP (lock_inv sh lock (Interp (lock_pred buf len)); cond_var sh cprod; cond_var sh ccon));
    [|forward; entailer].
  forward.
  forward_call tt.
  Intro x; destruct x as (r, data).
  forward_call (lock, sh, lock_pred buf len).
  simpl.
  Intro reqs; normalize.
  forward.
  unfold Znth; simpl.
  forward_while (EX reqs : list val,
   PROP (Forall isptr reqs; (length reqs <= MAX)%nat)
   LOCAL (temp _len (Vint (Int.repr (Zlength reqs))); temp _request r; temp _arg y; gvar _buf buf;
          gvar _length len; gvar _requests_lock lock;
          gvar _requests_producer cprod; gvar _requests_consumer ccon)
   SEP (data_at Ews (tarray (tptr trequest) (Z.of_nat MAX)) (complete reqs) buf;
        data_at Ews (tarray tint 1) [Vint (Int.repr (Zlength reqs))] len;
        fold_right sepcon emp (map Interp (map (fun r => Exp _ (fun data =>
          Data_at CompSpecs Tsh trequest (Vint (Int.repr data)) r)) reqs));
        lock_inv sh lock (Interp (lock_pred buf len));
        @data_at CompSpecs Tsh trequest (Vint (Int.repr data)) r;
        cond_var sh cprod; cond_var sh ccon)).
  (* Unfortunately, Delta now contains an equality involving unfold_reptype that causes a discriminate
     in fancy_intros (in saturate_local) to go into an infinite loop. *)
  - Exists reqs; go_lower; entailer'.
  - go_lower; entailer'.
  - forward_call (cprod, lock, sh, sh, lock_pred buf len).
    { simpl.
      Exists reqs0; unfold fold_right at 3; cancel.
      entailer'; cancel. }
    simpl.
    Intro reqs'; normalize.
    forward.
    Exists reqs'; go_lower; entailer'; cancel.
  - assert (length reqs0 < MAX)%nat.
    { rewrite Nat2Z.inj_lt; rewrite Zlength_correct, Int.signed_repr in HRE; auto.
      pose proof Int.min_signed_neg; split; [omega|].
      transitivity (Z.of_nat MAX); Omega0. }
    forward_call (r, buf, len, reqs0).
    { simpl; cancel. }
    forward.
    rewrite data_at_isptr, field_at_isptr; normalize.
    rewrite (data_at_isptr _ trequest); normalize.
    forward_call (lock, sh, lock_pred buf len).
    { simpl.
      Exists (reqs0 ++ [r]); timeout 10 cancel.
      unfold fold_right at 2; unfold fold_right at 1; cancel.
      unfold upd_Znth; simpl.
      rewrite sublist.sublist_nil.
      repeat rewrite Zlength_correct; rewrite app_length; simpl.
      rewrite Nat2Z.inj_add.
      repeat rewrite map_app; simpl; rewrite sepcon_app; simpl.
      unfold fold_right at 1; cancel; entailer'.
      Exists data; cancel.
      eapply derives_trans; [|apply prop_and_same_derives']; [cancel|].
      split; [rewrite Forall_app; auto | omega]. }
    { split; auto; split; simpl.
      + apply inv_precise; auto.
      + apply inv_positive. }
    forward_call (ccon, sh).
    go_lower; entailer'; cancel.
Qed.

Lemma body_consumer : semax_body Vprog Gprog f_consumer consumer_spec.
Proof.
  start_function.
  normalize.
  eapply semax_loop with (Q' := PROP ()
    LOCAL (temp _arg y; gvar _buf buf; gvar _length len; gvar _requests_lock lock;
           gvar _requests_producer cprod; gvar _requests_consumer ccon)
    SEP (lock_inv sh lock (Interp (lock_pred buf len)); cond_var sh cprod; cond_var sh ccon));
    [|forward; entailer].
  forward.
  forward_call (lock, sh, lock_pred buf len).
  simpl.
  Intro reqs; normalize.
  forward.
  unfold Znth; simpl.
  forward_while (EX reqs : list val, PROP (Forall isptr reqs; (length reqs <= MAX)%nat)
   LOCAL (temp _len (Vint (Int.repr (Zlength reqs))); temp _arg y; gvar _buf buf;
          gvar _length len; gvar _requests_lock lock;
          gvar _requests_producer cprod; gvar _requests_consumer ccon)
   SEP (data_at Ews (tarray (tptr trequest) (Z.of_nat MAX)) (complete reqs) buf;
        data_at Ews (tarray tint 1) [Vint (Int.repr (Zlength reqs))] len;
        fold_right sepcon emp (map Interp (map (fun r => Exp _ (fun data =>
          Data_at CompSpecs Tsh trequest (Vint (Int.repr data)) r)) reqs));
        lock_inv sh lock (Interp (lock_pred buf len));
        cond_var sh cprod; cond_var sh ccon)).
  - Exists reqs; entailer.
  - entailer.
  - forward_call (ccon, lock, sh, sh, lock_pred buf len).
    { simpl.
      Exists reqs0; entailer!.
      unfold fold_right at 1; cancel. }
    simpl.
    Intro reqs'; normalize.
    forward.
    Exists reqs'; entailer!.
  - assert (reqs0 <> []) as Hreqs.
    { intro; subst; unfold Zlength in *; simpl in *; contradiction HRE; auto. }
    rewrite (app_removelast_last (Vint (Int.repr 0)) Hreqs) in *.
    rewrite Zlength_correct, app_length; simpl.
    rewrite Nat2Z.inj_add, <- Zlength_correct; simpl.
    rewrite app_length in *; simpl in *.
    match goal with H : Forall isptr (_ ++ _) |- _ =>
      rewrite Forall_app in H; destruct H as (? & Hlast); inv Hlast end.
    forward_call (buf, len, removelast reqs0, last reqs0 (Vint (Int.repr 0))).
    { simpl; cancel. }
    { split; auto; omega. }
    forward.
    rewrite data_at_isptr, field_at_isptr; normalize.
    forward_call (lock, sh, lock_pred buf len).
    { simpl.
      Exists (removelast reqs0); entailer!.
      unfold upd_Znth; simpl.
      rewrite sublist.sublist_nil.
      rewrite Z.add_simpl_r.
      unfold fold_right at 1.
      repeat rewrite map_app; simpl; rewrite sepcon_app; cancel. }
    { split; auto; split; simpl.
      + apply inv_precise; auto.
      + apply inv_positive. }
    forward_call (cprod, sh).
    { simpl; cancel. }
    Intro data.
    forward_call (last reqs0 (Vint (Int.repr 0)), data).
    { simpl; cancel. }
    unfold fold_right; entailer!.
Qed.

Lemma repeat_plus : forall A (x : A) i j, repeat x (i + j) = repeat x i ++ repeat x j.
Proof.
  induction i; auto; simpl; intro.
  rewrite IHi; auto.
Qed.

Lemma body_main:  semax_body Vprog Gprog f_main main_spec.
Proof.
  start_function.
  rewrite <- (sepcon_emp (main_pre _ _)).
  rewrite main_pre_start; unfold prog_vars, prog_vars'; simpl globvars2pred.
  process_idstar.
  simpl init_data2pred'.
  rewrite <- (sepcon_emp (_ * _)).
  simple apply move_globfield_into_SEP.
  rewrite sepcon_emp.
  process_idstar.
  simpl init_data2pred'.
  rewrite <- (sepcon_emp (_ * _)).
  simple apply move_globfield_into_SEP.
  rewrite sepcon_emp.
  process_idstar.
  simpl init_data2pred'.
  rewrite <- (sepcon_emp (_ * _)).
  simple apply move_globfield_into_SEP.
  rewrite sepcon_emp.
  process_idstar.
  simpl init_data2pred'.
  rewrite <- (sepcon_emp (_ * _)).
  simple apply move_globfield_into_SEP.
  rewrite sepcon_emp.
  process_idstar.
  simpl init_data2pred'.
  rewrite <- (sepcon_emp (_ * _)).
  simple apply move_globfield_into_SEP.
  change (globvars2pred nil) with (@emp (environ->mpred) _ _).
  repeat rewrite sepcon_emp.
  rewrite <- seq_assoc.
  apply semax_seq' with (P' := PROP ( )
    LOCAL (gvar _buf gvar4; gvar _requests_producer gvar3; gvar _requests_consumer gvar2;
           gvar _length gvar1; gvar _requests_lock gvar0)
    SEP (data_at Ews (tarray (tptr trequest) (Z.of_nat MAX)) (repeat (Vint (Int.repr 0)) MAX) gvar4;
         data_at_ Ews tint gvar3; data_at_ Ews tint gvar2;
         data_at_ Ews (tarray tint 1) gvar1;
         data_at_ Ews (Tstruct 3%positive noattr) gvar0)).
  { eapply semax_for_const_bound_const_init with (P := fun _ => [])
      (Q := fun _ => [gvar _buf gvar4; gvar _requests_producer gvar3; gvar _requests_consumer gvar2; gvar _length gvar1; 
                      gvar _requests_lock gvar0])
      (R := fun i => [data_at Ews (tarray (tptr trequest) (Z.of_nat MAX))
             (repeat (Vint (Int.repr 0)) (Z.to_nat i) ++ repeat Vundef (Z.to_nat (10 - i))) gvar4;
             data_at_ Ews tint gvar3; data_at_ Ews tint gvar2;
             data_at_ Ews (tarray tint 1) gvar1; data_at_ Ews tlock gvar0]);
    [reflexivity | try repable_signed | try repable_signed | reflexivity | try reflexivity; omega
    | intro; unfold map at 1; auto 50 with closed
    | cbv beta; simpl update_tycon
    | intro; cbv beta; simpl update_tycon; try solve [entailer!]
    | try apply semax_for_resolve_postcondition
    | intro; cbv beta; simpl update_tycon; abbreviate_semax;
      try (apply semax_extract_PROP; intro) ]; try computable.
    { unfold tlock, semax_conc._lock_t, trequest, _request_t; entailer!. }
    { unfold normal_ret_assert, tlock, semax_conc._lock_t; entailer!. }
    forward.
    entailer!.
    assert (Zlength (repeat (Vint (Int.repr 0)) (Z.to_nat i)) = i) as Hlen.
    { rewrite Zlength_correct, repeat_length.
      apply Z2Nat.id; omega. }
    rewrite upd_Znth_app2; rewrite Hlen; [|rewrite Zlength_correct; Omega0].
    assert (0 < Z.to_nat (10 - i))%nat by Omega0.
    destruct (Z.to_nat (10 - i)) eqn: Hminus; [omega | simpl].
    rewrite Zminus_diag; unfold upd_Znth, sublist.sublist; simpl.
    rewrite Zlength_cons; unfold Z.succ; simpl.
    rewrite Z.add_simpl_r, Zlength_correct, Nat2Z.id, firstn_exact_length.
    rewrite Z2Nat.inj_add; try omega.
    rewrite repeat_plus; simpl.
    rewrite <- app_assoc; replace (Z.to_nat (10 - (i + 1))) with n; auto.
    rewrite Z.sub_add_distr.
    rewrite Z2Nat.inj_sub; [|omega].
    rewrite Hminus; simpl; omega. }
  forward.
  forward_call (gvar0, Ews, lock_pred gvar4 gvar1).
  { unfold tlock, semax_conc._lock_t; cancel. }
  rewrite (data_at_isptr _ (tarray _ _)), field_at_isptr; normalize.
  forward_call (gvar0, Ews, lock_pred gvar4 gvar1).
  { simpl.
    Exists ([] : list val); simpl; entailer!. }
  { split; auto; split.
    - apply inv_precise; auto.
    - apply inv_positive. }
  forward_call (gvar3, Ews).
  { unfold tcond; cancel. }
  forward_call (gvar2, Ews).
  { unfold tcond; cancel. }
  destruct split_Ews as (sh1 & sh2 & ? & ? & Hsh).
  get_global_function'' _consumer.
  normalize.
  apply extract_exists_pre; intros c_.
  forward_call (c_, Vint (Int.repr 0), existT (fun ty => ty * (ty -> val -> Pred))%type
   (val * val * share * val * val * val)%type ((gvar4, gvar1, sh1, gvar0, gvar3, gvar2),
   fun (x : (val * val * share * val * val * val)) (_ : val) => let '(buf, len, sh, lock, cprod, ccon) := x in
     Pred_list [Pred_prop (readable_share sh); Lock_inv sh lock (lock_pred buf len);
                Cond_var _ sh cprod; Cond_var _ sh ccon])).
  { simpl; entailer.
    Exists _arg; entailer.
    Exists (fun x : val * val * share * val * val * val => let '(buf, len, sh, lock, cprod, ccon) := x in
      [(_buf, buf); (_length, len); (_requests_lock, lock); (_requests_producer, cprod);
       (_requests_consumer, ccon)]); entailer.
    subst Frame; instantiate (1 := [cond_var sh2 gvar2; cond_var sh2 gvar3;
      lock_inv sh2 gvar0 (Interp (lock_pred gvar4 gvar1))]).
    evar (body : funspec); replace (WITH _ : _ PRE [_] _ POST [_] _) with body.
    repeat rewrite sepcon_assoc; apply sepcon_derives; subst body; [apply derives_refl|].
    simpl.
    erewrite <- (sepcon_assoc (cond_var sh1 gvar2)), cond_var_join; eauto; cancel.
    repeat rewrite sepcon_assoc.
    erewrite <- (sepcon_assoc (cond_var sh1 gvar3)), cond_var_join; eauto; cancel.
    erewrite lock_inv_join; eauto; cancel.
    subst body; f_equal.
    extensionality.
    destruct x as (?, (((((?, ?), ?), ?), ?), ?)); simpl.
    f_equal; f_equal.
    unfold SEPx; simpl; normalize. }
  { simpl; intros ? Hpred.
    destruct Hpred as (? & ? & ? & (? & ?) & ? & ? & ? & ? & ? & ? & ? & ? & ? & ? & ? & ? & Hemp).
    eapply almost_empty_join; eauto; [|eapply almost_empty_join; eauto;
      [|eapply almost_empty_join; eauto; [|eapply almost_empty_join; eauto]]].
    - eapply prop_almost_empty; eauto.
    - eapply lock_inv_almost_empty; eauto.
    - eapply cond_var_almost_empty; eauto.
    - eapply cond_var_almost_empty; eauto.
    - eapply emp_almost_empty; eauto. }
  forward_call (gvar0, sh2, lock_pred gvar4 gvar1).
  simpl.
  Intro reqs; normalize.
  forward.
  unfold Znth; simpl.
  forward_while (EX reqs : list val, PROP (Forall isptr reqs; (length reqs <= MAX)%nat)
   LOCAL (temp _len (Vint (Int.repr (Zlength reqs))); gvar _consumer c_; gvar _buf gvar4; gvar _requests_producer gvar3;
   gvar _requests_consumer gvar2; gvar _length gvar1; gvar _requests_lock gvar0)
   SEP (data_at Ews (tarray (tptr trequest) (Z.of_nat MAX)) (complete reqs) gvar4;
   data_at Ews (tarray tint 1) [Vint (Int.repr (Zlength reqs))] gvar1;
   fold_right sepcon emp
     (map Interp (map (fun r : val => Exp Z (fun data : Z => Data_at CompSpecs Tsh trequest (Vint (Int.repr data)) r)) reqs));
   lock_inv sh2 gvar0 (Interp (lock_pred gvar4 gvar1));
   cond_var sh2 gvar2; cond_var sh2 gvar3)).
  { Exists reqs; entailer!. }
  { entailer. }
  { (* loop body *)
    forward_call (gvar3, gvar0, sh2, sh2, lock_pred gvar4 gvar1).
    { simpl; cancel.
      Exists reqs0; unfold fold_right at 1; cancel; entailer!. }
    simpl; Intro reqs'; normalize.
    forward.
    Exists reqs'; entailer!. }
  forward_call (gvar0, sh2, lock_pred gvar4 gvar1).
  { simpl; Exists reqs0; cancel.
    unfold fold_right at 1; entailer!. }
  { split; auto; split; [apply inv_precise | apply inv_positive]; auto. }
  destruct (split_readable_share _ H0) as (sh2' & sh3 & ? & ? & Hsh').
  get_global_function'' _producer.
  normalize.
  apply extract_exists_pre; intros p_.
  forward_call (p_, Vint (Int.repr 0), existT (fun ty => ty * (ty -> val -> Pred))%type
   (val * val * share * val * val * val)%type ((gvar4, gvar1, sh2', gvar0, gvar3, gvar2),
   fun (x : (val * val * share * val * val * val)) (_ : val) => let '(buf, len, sh, lock, cprod, ccon) := x in
     Pred_list [Pred_prop (readable_share sh); Lock_inv sh lock (lock_pred buf len);
                Cond_var _ sh cprod; Cond_var _ sh ccon])).
  { simpl; entailer.
    Exists _arg; entailer.
    Exists (fun x : val * val * share * val * val * val => let '(buf, len, sh, lock, cprod, ccon) := x in
      [(_buf, buf); (_length, len); (_requests_lock, lock); (_requests_producer, cprod);
       (_requests_consumer, ccon)]); entailer.
    subst Frame; instantiate (1 := [cond_var sh3 gvar2; cond_var sh3 gvar3;
      lock_inv sh3 gvar0 (Interp (lock_pred gvar4 gvar1))]).
    evar (body : funspec); replace (WITH _ : _ PRE [_] _ POST [_] _) with body.
    repeat rewrite sepcon_assoc; apply sepcon_derives; subst body; [apply derives_refl|].
    simpl.
    erewrite <- (sepcon_assoc (cond_var sh2' gvar2)), cond_var_join; eauto; cancel.
    repeat rewrite sepcon_assoc.
    erewrite <- (sepcon_assoc (cond_var sh2' gvar3)), cond_var_join; eauto; cancel.
    erewrite lock_inv_join; eauto; cancel.
    subst body; f_equal.
    extensionality.
    destruct x as (?, (((((?, ?), ?), ?), ?), ?)); simpl.
    f_equal; f_equal.
    unfold SEPx; simpl; normalize. }
  { simpl; intros ? Hpred.
    destruct Hpred as (? & ? & ? & (? & ?) & ? & ? & ? & ? & ? & ? & ? & ? & ? & ? & ? & ? & Hemp).
    eapply almost_empty_join; eauto; [|eapply almost_empty_join; eauto;
      [|eapply almost_empty_join; eauto; [|eapply almost_empty_join; eauto]]].
    - eapply prop_almost_empty; eauto.
    - eapply lock_inv_almost_empty; eauto.
    - eapply cond_var_almost_empty; eauto.
    - eapply cond_var_almost_empty; eauto.
    - eapply emp_almost_empty; eauto. }
  rewrite <- seq_assoc.
  apply semax_seq' with (P' := PROP () LOCAL () SEP (FF)).
  { match goal with |- semax _ ?P _ _ => eapply semax_loop with (Q' := P) end;
      forward; entailer!. }
  forward.
Qed.

Definition extlink := ext_link_prog prog.

Definition Espec := add_funspecs (Concurrent_Espec unit _ extlink) extlink Gprog.
Existing Instance Espec.

Lemma all_funcs_correct:
  semax_func Vprog Gprog (prog_funct prog) Gprog.
Proof.
unfold Gprog, prog, prog_funct; simpl.
repeat (apply semax_func_cons_ext_vacuous; [reflexivity | ]).
semax_func_cons_ext.
{ admit. }
semax_func_cons_ext.
{ admit. }
semax_func_cons_ext.
{ admit. }
semax_func_cons_ext.
{ admit. }
semax_func_cons_ext.
{ admit. }
semax_func_cons_ext.
{ admit. }
semax_func_cons_ext.
{ admit. }
eapply semax_func_cons_ext; try reflexivity.
{ admit. }
{ admit. }
eapply semax_func_cons_ext; try reflexivity.
{ admit. }
{ admit. }
semax_func_cons body_process.
semax_func_cons body_get_request.
semax_func_cons body_process_request.
semax_func_cons body_add.
semax_func_cons body_remove.
semax_func_cons body_producer.
semax_func_cons body_consumer.
semax_func_cons body_main.
Admitted.
