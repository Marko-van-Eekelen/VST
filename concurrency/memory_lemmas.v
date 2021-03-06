Require Import compcert.common.Memory.
Require Import concurrency.permissions.
Require Import Coq.ZArith.ZArith.
Require Import compcert.lib.Coqlib.

(** ** Various results about CompCert's memory model*)
Module MemoryLemmas.

  Global Notation "a # b" := (Maps.PMap.get b a) (at level 1).
  Transparent Mem.store.
  (*TODO: see if we can reuse that for gsoMem_obs_eq.*)
  (*TODO: maybe we don't need to open up the interface here*)
  Lemma store_contents_other:
    forall m m' b b' ofs ofs' v chunk
      (Hstore: Mem.store chunk m b ofs v = Some m')
      (Hstable: ~ Mem.perm m b' ofs' Cur Writable),
      Maps.ZMap.get ofs' (Mem.mem_contents m') # b' =
      Maps.ZMap.get ofs' (Mem.mem_contents m) # b'.
  Proof.
    intros.
    erewrite Mem.store_mem_contents; eauto.
    simpl.
    destruct (Pos.eq_dec b b') as [Heq | Hneq];
      [| by erewrite Maps.PMap.gso by auto].
    subst b'.
    rewrite Maps.PMap.gss.
    destruct (Z_lt_le_dec ofs' ofs) as [Hlt | Hge].
    erewrite Mem.setN_outside by (left; auto);
      by reflexivity.
    destruct (Z_lt_ge_dec
                ofs' (ofs + (size_chunk chunk)))
      as [Hlt | Hge'].
    (* case the two addresses coincide - contradiction*)
    apply Mem.store_valid_access_3 in Hstore.
    unfold Mem.valid_access in Hstore. simpl in Hstore.
    destruct Hstore as [Hcontra _].
    unfold Mem.range_perm in Hcontra.
    specialize (Hcontra ofs' (conj Hge Hlt));
      by exfalso.
    erewrite Mem.setN_outside by (right; rewrite size_chunk_conv in Hge';
                                    by rewrite encode_val_length);
      by auto.
  Qed.

  Transparent Mem.alloc.
  
  Lemma val_at_alloc_1:
    forall m m' sz nb b ofs
      (Halloc: Mem.alloc m 0 sz = (m', nb))
      (Hvalid: Mem.valid_block m b),
      Maps.ZMap.get ofs (Maps.PMap.get b (Mem.mem_contents m)) =
      Maps.ZMap.get ofs (Maps.PMap.get b (Mem.mem_contents m')).
  Proof.
    intros.
    unfold Mem.alloc in Halloc.
    inv Halloc.
    simpl.
    rewrite Maps.PMap.gso; auto.
    intro; subst. unfold Mem.valid_block in *.
    eapply Plt_strict; eauto.
  Qed.

  Lemma val_at_alloc_2:
    forall m m' sz nb ofs
      (Halloc: Mem.alloc m 0 sz = (m', nb)),
      Maps.ZMap.get ofs (Maps.PMap.get nb (Mem.mem_contents m')) = Undef.
  Proof.
    intros.
    unfold Mem.alloc in Halloc.
    inv Halloc.
    simpl.
    rewrite PMap.gss, ZMap.gi.
    reflexivity.
  Qed.

  (*stronger version of val_at_alloc_1*)
  Lemma val_at_alloc_3:
    forall m m' sz nb b ofs
      (Halloc: Mem.alloc m 0 sz = (m', nb))
      (Hvalid: b <> nb),
      Maps.ZMap.get ofs (Maps.PMap.get b (Mem.mem_contents m)) =
      Maps.ZMap.get ofs (Maps.PMap.get b (Mem.mem_contents m')).
  Proof.
    intros.
    unfold Mem.alloc in Halloc.
    inv Halloc.
    simpl.
    rewrite Maps.PMap.gso; auto.
  Qed.

  Lemma permission_at_alloc_1:
    forall m m' lo hi nb b ofs
      (Halloc: Mem.alloc m lo hi = (m', nb))
      (Hvalid: Mem.valid_block m b),
    forall k, permissions.permission_at m b ofs k =
         permissions.permission_at m' b ofs k.
  Proof.
    intros.
    Transparent Mem.alloc.
    unfold Mem.alloc in Halloc.
    inv Halloc.
    unfold permissions.permission_at. simpl.
    rewrite Maps.PMap.gso; auto.
    intro; subst. unfold Mem.valid_block in *.
    eapply Plt_strict; eauto.
  Qed.

  Lemma permission_at_alloc_2:
    forall m m' sz nb ofs
      (Halloc: Mem.alloc m 0 sz = (m', nb))
      (Hofs: (0 <= ofs < sz)%Z),
      forall k, permissions.permission_at m' nb ofs k = Some Freeable.
  Proof.
    intros.
    unfold Mem.alloc in Halloc.
    inv Halloc.
    unfold permissions.permission_at. simpl.
    rewrite Maps.PMap.gss.
    rewrite threads_lemmas.if_true; auto.
    destruct (zle 0 ofs), (zlt ofs sz); auto;
    try omega.
  Qed.

  Lemma permission_at_alloc_3:
    forall m m' sz nb ofs
      (Halloc: Mem.alloc m 0 sz = (m', nb))
      (Hofs: (ofs < 0 \/ ofs >= sz)%Z),
      forall k, permissions.permission_at m' nb ofs k = None.
  Proof.
    intros.
    unfold Mem.alloc in Halloc.
    inv Halloc.
    unfold permissions.permission_at. simpl.
    rewrite Maps.PMap.gss.
    rewrite threads_lemmas.if_false; auto.
    apply negb_true_iff.
    destruct (zle 0 ofs), (zlt ofs sz); auto;
    omega.
  Qed.

  Lemma permission_at_free_1 :
    forall m m' (lo hi : Z) b b' ofs'
      (Hfree: Mem.free m b lo hi = Some m')
      (Hnon_freeable: ~ Mem.perm m b' ofs' Cur Freeable),
    forall k : perm_kind,
      permission_at m b' ofs' k = permission_at m' b' ofs' k.
  Proof.
    intros.
    pose proof (Mem.free_result _ _ _ _ _ Hfree) as Hfree'.
    subst.
    unfold Mem.unchecked_free. unfold permission_at. simpl.
    destruct (Pos.eq_dec b' b); subst.
    - destruct (zle lo ofs' && zlt ofs' hi) eqn:Hintv.
      + exfalso.
        apply andb_true_iff in Hintv.
        destruct Hintv as [Hle Hlt].
        destruct (zle lo ofs'); simpl in *; auto.
        destruct (zlt ofs' hi); simpl in *; auto.
        apply Mem.free_range_perm in Hfree.
        unfold Mem.range_perm in Hfree.
        specialize (Hfree ofs' (conj l l0)).
        auto.
      + rewrite Maps.PMap.gss.
        rewrite Hintv.
        reflexivity.
    - rewrite Maps.PMap.gso;
      auto.
  Qed.
  
  Lemma permission_at_free_list_1:
    forall m m' l b ofs
      (Hfree: Mem.free_list m l = Some m')
      (Hnon_freeable: ~ Mem.perm m b ofs Cur Freeable),
    forall k : perm_kind,
      permission_at m b ofs k = permission_at m' b ofs k.
  Proof.
    intros m m' l.
    generalize dependent m.
    induction l; intros.
    - simpl in Hfree; inv Hfree; reflexivity.
    - simpl in Hfree. destruct a, p.
      destruct (Mem.free m b0 z0 z) eqn:Hfree'; try discriminate.
      pose proof Hfree' as Hfree''.
      eapply permission_at_free_1 with (k := k) in Hfree'; eauto.
      eapply permission_at_free_1 with (k := Cur) in Hfree''; eauto.
      rewrite Hfree'. eapply IHl; eauto.
      unfold Mem.perm in *. unfold permission_at in *.
      rewrite <- Hfree''. assumption.
  Qed.
  
  Lemma mem_free_contents:
    forall m m2 sz b
      (Hfree: Mem.free m b 0 sz = Some m2),
    forall b' ofs,
      Maps.ZMap.get ofs (Maps.PMap.get b' (Mem.mem_contents m)) =
      Maps.ZMap.get ofs (Maps.PMap.get b' (Mem.mem_contents m2)).
  Proof.
    intros.
    apply Mem.free_result in Hfree.
    subst; unfold Mem.unchecked_free.
    reflexivity.
  Qed.

  Lemma mem_store_max:
    forall chunk b ofs v m m',
      Mem.store chunk m b ofs v = Some m' ->
      forall b' ofs',
        (getMaxPerm m) # b' ofs' = (getMaxPerm m') # b' ofs'.
  Proof.
    intros.
    unfold Mem.store in *.
    destruct (Mem.valid_access_dec m chunk b ofs Writable); try discriminate.
    inversion H; subst.
    do 2 rewrite getMaxPerm_correct.
    reflexivity.
  Qed.

  Lemma mem_storebytes_cur :
    forall b (ofs : Z) bytes (m m' : mem),
      Mem.storebytes m b ofs bytes = Some m' ->
      forall (b' : positive) (ofs' : Z),
        (getCurPerm m) !! b' ofs' = (getCurPerm m') !! b' ofs'.
  Proof.
    intros.
    Transparent Mem.storebytes.
    unfold Mem.storebytes in *.
    destruct (Mem.range_perm_dec m b ofs (ofs + Z.of_nat (length bytes)) Cur
                                 Writable); try discriminate.
    inversion H; subst.
    do 2 rewrite getCurPerm_correct.
    reflexivity.
  Qed.

  Lemma mem_store_cur:
    forall chunk b ofs v m m',
      Mem.store chunk m b ofs v = Some m' ->
      forall b' ofs',
        (getCurPerm m) # b' ofs' = (getCurPerm m') # b' ofs'.
  Proof.
    intros.
    apply Mem.store_storebytes in H.
    eapply mem_storebytes_cur; eauto.
  Qed.
  
  Lemma load_valid_block:
    forall (m : mem) b ofs chunk v,
      Mem.load chunk m b ofs = Some v ->
      Mem.valid_block m b.
  Proof.
    intros m b ofs chunk v Hload.
    apply Mem.load_valid_access in Hload.
    apply Mem.valid_access_valid_block with (chunk:=chunk) (ofs:= ofs).
    eapply Mem.valid_access_implies; eauto.
    constructor.
  Qed.
  
End MemoryLemmas.