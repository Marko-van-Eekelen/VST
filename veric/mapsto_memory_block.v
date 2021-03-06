Require Import msl.log_normalize.
Require Import msl.alg_seplog.
Require Import veric.base.
Require Import veric.compcert_rmaps.
Require Import veric.slice.
Require Import veric.res_predicates.
Require Import veric.Clight_lemmas.
Require Import veric.tycontext.
Require Import veric.expr2.
Require Import veric.expr_lemmas3.
Require Import veric.binop_lemmas2.
Require Import veric.address_conflict.
Require Import veric.shares.

Definition assert := environ -> mpred.  (* Unfortunately
   can't export this abbreviation through SeparationLogic.v because
  it confuses the Lift system *)

Lemma address_mapsto_exists:
  forall ch v rsh (sh: pshare) loc w0
      (RESERVE: forall l', adr_range loc (size_chunk ch) l' -> w0 @ l' = NO Share.bot),
      (align_chunk ch | snd loc) ->
      exists w, address_mapsto ch (decode_val ch (encode_val ch v)) rsh (pshare_sh sh) loc w 
                    /\ core w = core w0.
Proof.  exact address_mapsto_exists. Qed.

Definition permission_block (sh: Share.t)  (v: val) (t: type) : mpred :=
    match access_mode t with
         | By_value ch => 
            match v with 
            | Vptr b ofs => 
                 nonlock_permission_bytes sh (b, Int.unsigned ofs)
                       (size_chunk ch)
            | _ => FF
            end
         | _ => FF
         end.

Local Open Scope pred.

Definition mapsto (sh: Share.t) (t: type) (v1 v2 : val): mpred :=
  match access_mode t with
  | By_value ch => 
   match type_is_volatile t with
   | false =>
    match v1 with
     | Vptr b ofs => 
       if readable_share_dec sh
       then (!!tc_val t v2 &&
             address_mapsto ch v2
              (Share.unrel Share.Lsh sh) (Share.unrel Share.Rsh sh) (b, Int.unsigned ofs)) ||
            (!! (v2 = Vundef) &&
             EX v2':val, address_mapsto ch v2'
              (Share.unrel Share.Lsh sh) (Share.unrel Share.Rsh sh) (b, Int.unsigned ofs))
       else !! (tc_val' t v2 /\ (align_chunk ch | Int.unsigned ofs)) && nonlock_permission_bytes sh (b, Int.unsigned ofs) (size_chunk ch)
     | _ => FF
    end
    | _ => FF
    end
  | _ => FF
  end.

Definition mapsto_ sh t v1 := mapsto sh t v1 Vundef.

Lemma address_mapsto_readable:
  forall m v rsh sh a, address_mapsto m v rsh sh a |-- 
           !! readable_share (Share.splice rsh sh).
Proof.
intros.
unfold address_mapsto.
unfold derives.
simpl.
intros ? ?.
destruct H as [bl [[? [? ?]] ?]]. do 3 red.
specialize (H2 a). hnf in H2.
rewrite if_true in H2.
destruct H2 as [p ?].
clear - p.
apply right_nonempty_readable.
intros ?.
apply identity_share_bot in H. subst.
apply (p Share.bot).
split. apply Share.glb_bot. apply Share.lub_bot.
destruct a; split; auto.
clear; pose proof (size_chunk_pos m); omega.
Qed.

Lemma mapsto_tc_val': forall sh t p v, mapsto sh t p v |-- !! tc_val' t v.
Proof.
  intros.
  unfold mapsto.
  destruct (access_mode t); auto.
  if_tac; auto.
  destruct p; auto.
  if_tac.
  + apply orp_left; apply andp_left1.
    - intros ?; simpl.
      apply tc_val_tc_val'.
    - intros ? ?; simpl in *; subst.
      apply tc_val'_Vundef.
  + apply andp_left1.
    intros ?; simpl; tauto.
Qed.

Lemma mapsto_value_range:
 forall sh v sz sgn i, 
   readable_share sh ->
   mapsto sh (Tint sz sgn noattr) v (Vint i) =
    !! int_range sz sgn i && mapsto sh (Tint sz sgn noattr) v (Vint i).
Proof.
intros.
rename H into Hsh.
assert (GG: forall a b, (a || !!(Vint i = Vundef) && b) = a). {
intros. apply pred_ext; intros ? ?. hnf in H.
destruct H; auto; hnf in H; destruct H; discriminate.
left; auto.
}
apply pred_ext; [ | apply andp_left2; auto].
assert (MAX: Int.max_signed = 2147483648 - 1) by reflexivity.
assert (MIN: Int.min_signed = -2147483648) by reflexivity.
assert (Byte.min_signed = -128) by reflexivity.
assert (Byte.max_signed = 128-1) by reflexivity.
assert (Byte.max_unsigned = 256-1) by reflexivity.
destruct (Int.unsigned_range i).
assert (Int.modulus = Int.max_unsigned + 1) by reflexivity.
assert (Int.modulus = 4294967296) by reflexivity.
apply andp_right; auto.
unfold mapsto; intros.
replace (type_is_volatile (Tint sz sgn noattr)) with false
  by (destruct sz,sgn; reflexivity).
simpl.
destruct (readable_share_dec sh); [| tauto].
destruct sz, sgn, v; (try rewrite FF_and; auto);
 repeat rewrite GG;
 apply prop_andp_left; intros ? ? _; hnf; try omega.
 pose proof (Int.signed_range i); omega.
 destruct H6; subst; 
  try rewrite Int.unsigned_zero; try rewrite Int.unsigned_one; omega.
 destruct H6; subst; 
  try rewrite Int.unsigned_zero; try rewrite Int.unsigned_one; omega.
Qed.

Definition writable_block (id: ident) (n: Z): assert :=
   fun rho => 
        EX b: block,  EX rsh: Share.t,
          !! (ge_of rho id = Some b) && VALspec_range n rsh Share.top (b, 0).

Fixpoint writable_blocks (bl : list (ident*Z)) : assert :=
 match bl with
  | nil =>  fun rho => emp 
  | (b,n)::bl' =>  fun rho => writable_block b n rho * writable_blocks bl' rho
 end.

Fixpoint address_mapsto_zeros (sh: share) (n: nat) (adr: address) : mpred :=
 match n with
 | O => emp
 | S n' => address_mapsto Mint8unsigned (Vint Int.zero)
                (Share.unrel Share.Lsh sh) (Share.unrel Share.Rsh sh) adr 
               * address_mapsto_zeros sh n' (fst adr, Zsucc (snd adr))
end.

Definition address_mapsto_zeros' (n: Z) : spec :=
     fun (rsh sh: Share.t) (l: address) =>
          allp (jam (adr_range_dec l (Zmax n 0))
                                  (fun l' => yesat NoneP (VAL (Byte Byte.zero)) rsh sh l')
                                  noat).

Lemma address_mapsto_zeros_eq:
  forall sh n,
   address_mapsto_zeros sh n =
   address_mapsto_zeros' (Z_of_nat n) 
            (Share.unrel Share.Lsh sh) (Share.unrel Share.Rsh sh).
Proof.
  induction n;
  extensionality adr; destruct adr as [b i].
  * (* base case *)
    simpl.
    unfold address_mapsto_zeros'.
    apply pred_ext.
    intros w ?.
    intros [b' i'].
    hnf.
    rewrite if_false.
    simpl. apply resource_at_identity; auto.
    intros [? ?]. unfold Zmax in H1;  simpl in H1. omega.
    intros w ?.
    simpl.
    apply all_resource_at_identity.
    intros [b' i'].
    specialize (H (b',i')).
    hnf in H.
    rewrite if_false in H. apply H.
    clear; intros [? ?]. unfold Zmax in H0; simpl in H0. omega.
  * (* inductive case *)
    rewrite inj_S.
    simpl.
    rewrite IHn; clear IHn.
    apply pred_ext; intros w ?.
    - (* forward case *)
      destruct H as [w1 [w2 [? [? ?]]]].
      intros [b' i'].
      hnf.
      if_tac.
      + destruct H0 as [bl [[? [? ?]] ?]].
        specialize (H5 (b',i')).
        hnf in H5.
        if_tac in H5.
       ** destruct H5 as [p ?]; exists p.
          hnf in H5.
          specialize (H1 (b',i')). hnf in H1. rewrite if_false in H1.
          assert (LEV := join_level _ _ _ H).
          Focus 1. {
            apply (resource_at_join _ _ _ (b',i')) in H.
            apply join_comm in H; apply H1 in H.
            rewrite H in H5.
            hnf. rewrite H5. f_equal.
            * f_equal.
              simpl. destruct H6. simpl in H7. replace (i'-i) with 0 by omega.
              unfold size_chunk_nat in H0. simpl in H0. 
              unfold nat_of_P in H0. simpl in H0.
              destruct bl; try solve [inv H0].
              destruct bl; inv H0.
              simpl.
              clear - H3.
              (* TODO: Clean up the following proof. *)
              destruct m; try solve [inv H3].
              rewrite decode_byte_val in H3.
              f_equal.
              assert (Int.zero_ext 8 (Int.repr (Byte.unsigned i)) = Int.repr 0) by
                (forget (Int.zero_ext 8 (Int.repr (Byte.unsigned i))) as j; inv H3; auto).
              clear H3.
              assert (Int.unsigned (Int.zero_ext 8 (Int.repr (Byte.unsigned i))) =
                  Int.unsigned Int.zero) by (f_equal; auto).
              rewrite Int.unsigned_zero in H0.
              clear H.
              rewrite Int.zero_ext_mod in H0 by (compute; split; congruence).
              rewrite Int.unsigned_repr in H0.
              rewrite Zdiv.Zmod_small in H0.
              assert (Byte.repr (Byte.unsigned i) = Byte.zero).
              apply f_equal; auto.
              rewrite Byte.repr_unsigned in H. auto.
              apply Byte.unsigned_range.
              clear.
              pose proof (Byte.unsigned_range i).
              destruct H; split; auto.
              apply Z.le_trans with Byte.modulus.
              omega.
              clear.
              compute; congruence.
            * f_equal; f_equal;
              destruct LEV; auto.
          } Unfocus. 
          destruct H2.
          intros [? ?].
          destruct H6.
          clear - H7 H9 H10. simpl in H10. omega.
       ** assert (LEV := join_level _ _ _ H).
          apply (resource_at_join _ _ _ (b',i')) in H.
          apply H5 in H.
          specialize (H1 (b',i')).
          hnf in H1.
          if_tac in H1.
         -- destruct H1 as [p ?]; exists p.
            hnf in H1|-*.
            rewrite H in H1; rewrite H1.
            f_equal. f_equal; f_equal; destruct LEV; auto.
         -- contradiction H6.
            destruct H2.
            split; auto.
            simpl.
            subst b'.
            clear - H7 H8.
            assert (~ (Zsucc i <= i' < (Zsucc i + Zmax (Z_of_nat n) 0))).
            contradict H7; split; auto.
            clear H7.
            replace (Zmax (Zsucc (Z_of_nat n)) 0) with (Zsucc (Z_of_nat n)) in H8.
            replace (Zmax (Z_of_nat n) 0) with (Z_of_nat n) in H.
            omega.
            symmetry; apply Zmax_left.
            apply Z_of_nat_ge_O.
            symmetry; apply Zmax_left.
            clear.
            pose proof (Z_of_nat_ge_O n). omega.
      + apply (resource_at_join _ _ _ (b',i')) in H.
        destruct H0 as [bl [[? [? ?]] ?]].
        specialize (H5 (b',i')); specialize (H1 (b',i')).
        hnf in H1,H5.
        rewrite if_false in H5.
        rewrite if_false in H1.
       ** apply H5 in H.
          simpl in H1|-*.
          rewrite <- H; auto.
       ** clear - H2; contradict H2.
          destruct H2; split; auto.
          destruct H0.
          split; try omega.
          pose proof (Z_of_nat_ge_O n). 
          rewrite Zmax_left in H1 by omega.
          rewrite Zmax_left by omega.
          omega.
       ** clear - H2; contradict H2; simpl in H2.
          destruct H2; split; auto.
          rewrite Zmax_left by omega.
          omega.

    - (* backward direction *)
      forget (Share.unrel Share.Lsh sh) as rsh.
      forget (Share.unrel Share.Rsh sh) as sh'. clear sh; rename sh' into sh.
      assert (H0 := H (b,i)).
      hnf in H0.
      rewrite if_true in H0
        by (split; auto; pose proof (Z_of_nat_ge_O n); rewrite Zmax_left; omega).
      destruct H0 as [H0 H1].
      assert (AV.valid (res_option oo (fun loc => if eq_dec loc (b,i) then 
       YES rsh (mk_pshare _ H0) (VAL (Byte Byte.zero)) NoneP 
          else core (w @ loc)))).
      Focus 1. {
        intros b' z'; unfold res_option, compose; if_tac; simpl; auto.
        destruct (w @ (b',z')); [rewrite core_NO | rewrite core_YES | rewrite core_PURE]; auto.  
      } Unfocus.
      destruct (make_rmap _ H2 (level w)) as [w1 [? ?]].
      extensionality loc. unfold compose.
      if_tac; [unfold resource_fmap; f_equal; apply preds_fmap_NoneP 
           | apply resource_fmap_core].
      assert (AV.valid (res_option oo 
        fun loc => if adr_range_dec (b, Zsucc i) (Z.max (Z.of_nat n) 0) loc
                       then YES rsh (mk_pshare _ H0) (VAL (Byte Byte.zero)) NoneP 
          else core (w @ loc))).
      Focus 1. {
        intros b' z'; unfold res_option, compose; if_tac; simpl; auto. 
        case_eq (w @ (b',z')); intros;
         [rewrite core_NO | rewrite core_YES | rewrite core_PURE]; auto.
      } Unfocus.
      destruct (make_rmap _ H5 (level w)) as [w2 [? ?]].
      extensionality loc. unfold compose.
      if_tac; [unfold resource_fmap; f_equal; apply preds_fmap_NoneP 
           | apply resource_fmap_core].
      exists w1; exists w2; split3; auto.
+apply resource_at_join2; try congruence.
  intro loc; rewrite H4; rewrite H7.
 clear - H.
 specialize (H loc).  unfold jam in H. hnf in H.
 rewrite Zmax_left by (pose proof (Z_of_nat_ge_O n); omega).
 rewrite Zmax_left in H by (pose proof (Z_of_nat_ge_O n); omega).
 if_tac. rewrite if_false.
 subst. rewrite if_true in H.
  destruct H as [H' H]; rewrite H. rewrite core_YES.
 rewrite preds_fmap_NoneP.
 apply join_unit2.
 constructor. auto.
 repeat f_equal.
 apply mk_lifted_refl1.
 split; auto; omega.
 subst. intros [? ?]; omega.
 if_tac in H.
 rewrite if_true.
 destruct H as [H' H]; rewrite H; clear H. rewrite core_YES.
 rewrite preds_fmap_NoneP.
 apply join_unit1.
 constructor; auto.
 f_equal.
 apply mk_lifted_refl1.
 destruct loc;
 destruct H2; split; auto.
 assert (z<>i) by congruence.
 omega.
 rewrite if_false.
 unfold noat in H. simpl in H.
 apply join_unit1; [apply core_unit | ].
 clear - H.
 apply H. apply join_unit2. apply core_unit. auto.
 destruct loc. intros [? ?]; subst. apply H2; split; auto; omega.
+ exists (Byte Byte.zero :: nil); split.
 split. reflexivity. split.
 unfold decode_val. simpl. f_equal.
 apply Z.divide_1_l.
 intro loc. hnf. if_tac. exists H0.
 destruct loc as [b' i']. destruct H8; subst b'.
 simpl in H9. assert (i=i') by omega; subst i'.
 rewrite Zminus_diag. hnf. rewrite preds_fmap_NoneP.
  rewrite H4. rewrite if_true by auto. f_equal.
 unfold noat. simpl. rewrite H4. rewrite if_false. apply core_identity.
  contradict H8. subst. split; auto. simpl; omega.
+ intro loc. hnf. 
 if_tac. exists H0. hnf. rewrite H7.
 rewrite if_true by auto. rewrite preds_fmap_NoneP. auto.
 unfold noat. simpl. rewrite H7.
 rewrite if_false by auto. apply core_identity.
Qed.

Definition mapsto_zeros (n: Z) (sh: share) (a: val) : mpred :=
 match a with
  | Vptr b z => address_mapsto_zeros sh (nat_of_Z n)
                          (b, Int.unsigned z)
  | _ => TT
  end.

Fixpoint memory_block' (sh: share) (n: nat) (b: block) (i: Z) : mpred :=
  match n with
  | O => emp
  | S n' => mapsto_ sh (Tint I8 Unsigned noattr) (Vptr b (Int.repr i))
         * memory_block' sh n' b (i+1)
 end.

Definition memory_block'_alt (sh: share) (n: nat) (b: block) (ofs: Z) : mpred :=
 if readable_share_dec sh 
 then VALspec_range (Z_of_nat n)
               (Share.unrel Share.Lsh sh) (Share.unrel Share.Rsh sh) (b, ofs)
 else nonlock_permission_bytes sh (b,ofs) (Z.of_nat n).

Lemma memory_block'_eq: 
 forall sh n b i,
  0 <= i ->
  Z_of_nat n + i <= Int.modulus ->
  memory_block' sh n b i = memory_block'_alt sh n b i.
Proof.
  intros.
  unfold memory_block'_alt.
  revert i H H0; induction n; intros.
  + unfold memory_block'.
    simpl.
    rewrite VALspec_range_0, nonlock_permission_bytes_0.
    if_tac; auto.
  + unfold memory_block'; fold memory_block'.
    rewrite (IHn (i+1)) by (rewrite inj_S in H0; omega).
    symmetry.
    rewrite (VALspec_range_split2 1 (Z_of_nat n)) by (try rewrite inj_S; omega).
    rewrite VALspec1.
    unfold mapsto_, mapsto.
    simpl access_mode. cbv beta iota.
    change (type_is_volatile (Tint I8 Unsigned noattr)) with false. cbv beta iota.
    destruct (readable_share_dec sh).
    - f_equal.
      assert (i < Int.modulus) by (rewrite Nat2Z.inj_succ in H0; omega).
      rewrite Int.unsigned_repr by (unfold Int.max_unsigned; omega); clear H1.
      forget (Share.unrel Share.Lsh sh) as rsh.
      forget (Share.unrel Share.Rsh sh) as sh'.
      clear.

      assert (EQ: forall loc, jam (adr_range_dec loc (size_chunk Mint8unsigned)) = jam (eq_dec loc)).
      intros [b' z']; unfold jam; extensionality P Q loc;
       destruct loc as [b'' z'']; apply exist_ext; extensionality w;
       if_tac; [rewrite if_true | rewrite if_false]; auto;
        [destruct H; subst; f_equal;  simpl in H0; omega 
        | contradict H; inv H; split; simpl; auto; omega].
      apply pred_ext.
      * intros w ?.
        right; split; hnf; auto.
        assert (H':= H (b,i)).
        hnf in H'. rewrite if_true in H' by auto.
        destruct H' as [v H'].
        pose (l := v::nil).
        destruct v; [exists Vundef | exists (Vint (Int.zero_ext 8 (Int.repr (Byte.unsigned i0)))) | exists Vundef];
        exists l; (split; [ split3; [reflexivity |unfold l; (reflexivity || apply decode_byte_val) |  apply Z.divide_1_l ] | ]);
          rewrite EQ; intro loc; specialize (H loc);
         hnf in H|-*; if_tac; auto; subst loc; rewrite Zminus_diag;
         unfold l; simpl nth; auto.
      * apply orp_left.
        apply andp_left2.
        Focus 1. {
          intros w [l [[? [? ?]] ?]].
           intros [b' i']; specialize (H2 (b',i')); rewrite EQ in H2;
           hnf in H2|-*;  if_tac; auto. symmetry in H3; inv H3.
           destruct l; inv H. exists m.
           destruct H2 as [H2' H2]; exists H2'; hnf in H2|-*; rewrite H2.
           f_equal. f_equal. rewrite Zminus_diag. reflexivity.
        } Unfocus.
        Focus 1. {
          rewrite prop_true_andp by auto.
          intros w [v2' [l [[? [? ?]] ?]]].
           intros [b' i']; specialize (H2 (b',i')); rewrite EQ in H2;
           hnf in H2|-*;  if_tac; auto. symmetry in H3; inv H3.
           destruct l; inv H. exists m.
           destruct H2 as [H2' H2]; exists H2'; hnf in H2|-*; rewrite H2.
           f_equal. f_equal. rewrite Zminus_diag. reflexivity.
        } Unfocus.
    - rewrite Int.unsigned_repr by (rewrite Nat2Z.inj_succ in H0; unfold Int.max_unsigned; omega).
      change (size_chunk Mint8unsigned) with 1.
      rewrite prop_true_andp by (split; [apply tc_val'_Vundef | apply Z.divide_1_l]).
      apply nonlock_permission_bytes_split2.
      * rewrite Nat2Z.inj_succ; omega.
      * omega.
      * omega.
Qed.

Definition memory_block (sh: share) (n: Z) (v: val) : mpred :=
 match v with 
 | Vptr b ofs => (!!(Int.unsigned ofs + n <= Int.modulus)) && memory_block' sh (nat_of_Z n) b (Int.unsigned ofs)
 | _ => FF
 end.

Lemma mapsto__exp_address_mapsto: forall sh t b i_ofs ch,
  access_mode t = By_value ch ->
  type_is_volatile t = false ->
  readable_share sh ->
  mapsto_ sh t (Vptr b i_ofs) = EX  v2' : val,
            address_mapsto ch v2' (Share.unrel Share.Lsh sh)
              (Share.unrel Share.Rsh sh) (b, (Int.unsigned i_ofs)).
Proof.
  pose proof (@FF_orp (pred rmap) (algNatDed _)) as HH0.
  change seplog.orp with orp in HH0.
  change seplog.FF with FF in HH0.
  pose proof (@ND_prop_ext (pred rmap) (algNatDed _)) as HH1.
  change seplog.prop with prop in HH1.

  intros. rename H1 into RS.
  unfold mapsto_, mapsto.
  rewrite H, H0.
  rewrite if_true by auto.
  assert (!!(tc_val t Vundef) = FF)
    by (destruct t as [ | | | [ | ] |  | | | | ]; reflexivity).
  rewrite H1.
  
  rewrite FF_and, HH0.
  assert (!!(Vundef = Vundef) = TT) by (apply HH1; tauto).
  rewrite H2.
  rewrite TT_and.
  reflexivity.
Qed.

Lemma exp_address_mapsto_VALspec_range_eq:
  forall ch rsh sh l,
    EX v: val, address_mapsto ch v rsh sh l = !! (align_chunk ch | snd l) && VALspec_range (size_chunk ch) rsh sh l.
Proof.
  intros.
  apply pred_ext.
  + apply exp_left; intro.
    apply andp_right; [| apply address_mapsto_VALspec_range].
    unfold address_mapsto.
    apply exp_left; intro.
    apply andp_left1.
    apply (@prop_derives (pred rmap) (algNatDed _)); tauto.
  + apply prop_andp_left; intro.
    apply VALspec_range_exp_address_mapsto; auto.
Qed.

Lemma VALspec_range_exp_address_mapsto_eq:
  forall ch rsh sh l,
    (align_chunk ch | snd l) ->
    VALspec_range (size_chunk ch) rsh sh l = EX v: val, address_mapsto ch v rsh sh l.
Proof.
  intros.
  apply pred_ext.
  + apply VALspec_range_exp_address_mapsto; auto.
  + apply exp_left; intro; apply address_mapsto_VALspec_range.
Qed.

Lemma mapsto__memory_block: forall sh b ofs t ch, 
  access_mode t = By_value ch ->
  type_is_volatile t = false ->
  (align_chunk ch | Int.unsigned ofs) ->
  Int.unsigned ofs + size_chunk ch <= Int.modulus ->
  mapsto_ sh t (Vptr b ofs) = memory_block sh (size_chunk ch) (Vptr b ofs).
Proof.
  intros.
  unfold memory_block.
  rewrite memory_block'_eq.
  2: pose proof Int.unsigned_range ofs; omega.
  2: rewrite Coqlib.nat_of_Z_eq by (pose proof size_chunk_pos ch; omega); omega.
  destruct (readable_share_dec sh).
 *
  rewrite mapsto__exp_address_mapsto with (ch := ch); auto.
  unfold memory_block'_alt. rewrite if_true by auto.
  rewrite Coqlib.nat_of_Z_eq by (pose proof size_chunk_pos ch; omega).
  rewrite VALspec_range_exp_address_mapsto_eq by (exact H1).
  rewrite <- (TT_and (EX  v2' : val,
   address_mapsto ch v2' (Share.unrel Share.Lsh sh)
     (Share.unrel Share.Rsh sh) (b, Int.unsigned ofs))) at 1.
  f_equal.
  pose proof (@ND_prop_ext (pred rmap) _).
  simpl in H3.
  change TT with (!! True).
  apply H3.
  tauto.
 * unfold mapsto_, mapsto, memory_block'_alt.
   rewrite prop_true_andp by auto.
   rewrite H, H0.
  rewrite !if_false by auto.
   rewrite prop_true_andp by (split; [apply tc_val'_Vundef | auto]).
   rewrite Z2Nat.id by (pose proof (size_chunk_pos ch); omega).
   auto.
Qed.

Lemma nonreadable_memory_block_mapsto: forall sh b ofs t ch v, 
  ~ readable_share sh ->
  access_mode t = By_value ch ->
  type_is_volatile t = false ->
  (align_chunk ch | Int.unsigned ofs) ->
  Int.unsigned ofs + size_chunk ch <= Int.modulus ->
  tc_val' t v ->
  memory_block sh (size_chunk ch) (Vptr b ofs) = mapsto sh t (Vptr b ofs) v.
Proof.
  intros.
  unfold memory_block.
  rewrite memory_block'_eq.
  2: pose proof Int.unsigned_range ofs; omega.
  2: rewrite Coqlib.nat_of_Z_eq by (pose proof size_chunk_pos ch; omega); omega.
  destruct (readable_share_dec sh).
 * tauto.
 * unfold mapsto_, mapsto, memory_block'_alt.
   rewrite prop_true_andp by auto.
   rewrite H0, H1.
   rewrite !if_false by auto.
   rewrite prop_true_andp by auto.
   rewrite Z2Nat.id by (pose proof (size_chunk_pos ch); omega).
   auto.
Qed.

Lemma mapsto_share_join:
 forall sh1 sh2 sh t p v,
   join sh1 sh2 sh ->
   mapsto sh1 t p v * mapsto sh2 t p v = mapsto sh t p v.
Proof.
  intros.
  unfold mapsto.
  destruct (access_mode t) eqn:?; try solve [rewrite FF_sepcon; auto].
  destruct (type_is_volatile t) eqn:?; try solve [rewrite FF_sepcon; auto].
  destruct p; try solve [rewrite FF_sepcon; auto].
  destruct (readable_share_dec sh1), (readable_share_dec sh2).
  + rewrite if_true by (eapply join_sub_readable; [unfold join_sub; eauto | auto]).
    pose proof (@guarded_sepcon_orp_distr (pred rmap) (algNatDed _) (algSepLog _)).
    simpl in H0; rewrite H0 by (intros; subst; pose proof tc_val_Vundef t; tauto); clear H0.
    f_equal; f_equal.
    - apply address_mapsto_share_join.
      1: apply Share.unrel_join; auto.
      1: apply Share.unrel_join; auto.
      1: rewrite <- splice_unrel_unrel in r.
         apply right_nonempty_readable in r; apply nonidentity_nonunit in r; auto.
      1: rewrite <- splice_unrel_unrel in r0.
         apply right_nonempty_readable in r0; apply nonidentity_nonunit in r0; auto.
    - rewrite exp_sepcon1.
      pose proof (@exp_congr (pred rmap) (algNatDed _) val); simpl in H0; apply H0; clear H0; intro.
      rewrite exp_sepcon2.
      transitivity
       (address_mapsto m v0 (Share.unrel Share.Lsh sh1) (Share.unrel Share.Rsh sh1) (b, Int.unsigned i) *
        address_mapsto m v0 (Share.unrel Share.Lsh sh2) (Share.unrel Share.Rsh sh2) (b, Int.unsigned i)).
      * apply pred_ext; [| apply (exp_right v0); auto].
        apply exp_left; intro.
        pose proof (fun rsh1 sh0 rsh2 sh3 a => (@add_andp (pred rmap) (algNatDed _) _ _ (address_mapsto_value_cohere m v0 x rsh1 sh0 rsh2 sh3 a))).
        simpl in H0; rewrite H0; clear H0.
        apply normalize.derives_extract_prop'; intro; subst; auto.
      * apply address_mapsto_share_join.
        1: apply Share.unrel_join; auto.
        1: apply Share.unrel_join; auto.
        1: rewrite <- splice_unrel_unrel in r.
           apply right_nonempty_readable in r; apply nonidentity_nonunit in r; auto.
        1: rewrite <- splice_unrel_unrel in r0.
           apply right_nonempty_readable in r0; apply nonidentity_nonunit in r0; auto.
  + rewrite if_true by (eapply join_sub_readable; [unfold join_sub; eauto | auto]).
    rewrite distrib_orp_sepcon.
    f_equal; rewrite sepcon_comm, sepcon_andp_prop;
    pose proof (@andp_prop_ext (pred rmap) _);
    (simpl in H0; apply H0; clear H0; [reflexivity | intro]).
    - rewrite (address_mapsto_align _ _ (Share.unrel Share.Lsh sh)).
      rewrite (andp_comm (address_mapsto _ _ _ _ _)), sepcon_andp_prop1.
      pose proof (@andp_prop_ext (pred rmap) _); simpl in H1; apply H1; clear H1; intros.
      * apply tc_val_tc_val' in H0; tauto.
      * apply nonlock_permission_bytes_address_mapsto_join; auto.
    - rewrite exp_sepcon2.
      pose proof (@exp_congr (pred rmap) (algNatDed _) val); simpl in H1; apply H1; clear H1; intro.
      rewrite (address_mapsto_align _ _ (Share.unrel Share.Lsh sh)).
      rewrite (andp_comm (address_mapsto _ _ _ _ _)), sepcon_andp_prop1.
      pose proof (@andp_prop_ext (pred rmap) _); simpl in H1; apply H1; clear H1; intros.
      * subst; pose proof tc_val'_Vundef t. tauto.
      * apply nonlock_permission_bytes_address_mapsto_join; auto.
  + rewrite if_true by (eapply join_sub_readable; [unfold join_sub; eexists; apply join_comm in H; eauto | auto]).
    rewrite sepcon_comm, distrib_orp_sepcon.
    f_equal; rewrite sepcon_comm, sepcon_andp_prop;
    pose proof (@andp_prop_ext (pred rmap) _);
    (simpl in H0; apply H0; clear H0; [reflexivity | intro]).
    - rewrite (address_mapsto_align _ _ (Share.unrel Share.Lsh sh)).
      rewrite (andp_comm (address_mapsto _ _ _ _ _)), sepcon_andp_prop1.
      pose proof (@andp_prop_ext (pred rmap) _); simpl in H1; apply H1; clear H1; intros.
      * apply tc_val_tc_val' in H0; tauto.
      * apply nonlock_permission_bytes_address_mapsto_join; auto.
    - rewrite exp_sepcon2.
      pose proof (@exp_congr (pred rmap) (algNatDed _) val); simpl in H1; apply H1; clear H1; intro.
      rewrite (address_mapsto_align _ _ (Share.unrel Share.Lsh sh)).
      rewrite (andp_comm (address_mapsto _ _ _ _ _)), sepcon_andp_prop1.
      pose proof (@andp_prop_ext (pred rmap) _); simpl in H1; apply H1; clear H1; intros.
      * subst; pose proof tc_val'_Vundef t. tauto.
      * apply nonlock_permission_bytes_address_mapsto_join; auto.
  + rewrite if_false by (eapply join_unreadable_shares; eauto).
    rewrite sepcon_andp_prop1, sepcon_andp_prop2, <- andp_assoc, andp_dup.
    f_equal.
    apply nonlock_permission_bytes_share_join; auto.
Qed.

Lemma mapsto_mapsto_: forall sh t v v', mapsto sh t v v' |-- mapsto_ sh t v.
Proof. unfold mapsto_; intros.
  unfold mapsto.
  destruct (access_mode t); auto.
  destruct (type_is_volatile t); auto.
  destruct v; auto.
  if_tac.
  + apply orp_left.
    apply orp_right2.
    apply andp_left2.
    apply andp_right.
    - intros ? _; simpl; auto.
    - apply exp_right with v'; auto.
    - apply andp_left2. apply exp_left; intro v2'.
      apply orp_right2. apply andp_right; [intros ? _; simpl; auto |]. apply exp_right with v2'.
      auto.
  + apply andp_derives; [| auto].
    intros ? [? ?].
    split; auto.
    apply tc_val'_Vundef.
Qed.

Lemma mapsto_not_nonunit: forall sh t p v, ~ nonunit sh -> mapsto sh t p v |-- emp.
Proof.
  intros.
  unfold mapsto.
  destruct (access_mode t); try solve [apply FF_derives].
  destruct (type_is_volatile t); try solve [apply FF_derives].
  destruct p; try solve [apply FF_derives].
  if_tac.
  + apply readable_nonidentity in H0.
    apply nonidentity_nonunit in H0; tauto.
  + apply andp_left2.
    apply nonlock_permission_bytes_not_nonunit; auto.
Qed.

Lemma mapsto_pure_facts: forall sh t p v,
  mapsto sh t p v |-- !! ((exists ch, access_mode t = By_value ch) /\ isptr p).
Proof.
  intros.
  unfold mapsto.
  destruct (access_mode t); try solve [apply FF_derives].
  destruct (type_is_volatile t); try solve [apply FF_derives].
  destruct p; try solve [apply FF_derives].

  pose proof (@seplog.prop_right (pred rmap) (algNatDed _)).
  simpl in H; apply H; clear H.
  split.
  + eauto.
  + simpl; auto.
Qed.

Lemma mapsto_overlap: forall sh {cs: compspecs} t1 t2 p1 p2 v1 v2,
  nonunit sh ->
  pointer_range_overlap p1 (sizeof t1) p2 (sizeof t2) ->
  mapsto sh t1 p1 v1 * mapsto sh t2 p2 v2 |-- FF.
Proof.
  intros.
  unfold mapsto.
  destruct (access_mode t1) eqn:AM1; try (rewrite FF_sepcon; auto).
  destruct (access_mode t2) eqn:AM2; try (rewrite normalize.sepcon_FF; auto).
  destruct (type_is_volatile t1); try (rewrite FF_sepcon; auto).
  destruct (type_is_volatile t2); try (rewrite normalize.sepcon_FF; auto).
  destruct p1; try (rewrite FF_sepcon; auto).
  destruct p2; try (rewrite normalize.sepcon_FF; auto).
  if_tac.
  + apply derives_trans with ((EX  v : val,
          address_mapsto m v (Share.unrel Share.Lsh sh)
            (Share.unrel Share.Rsh sh) (b, Int.unsigned i)) *
      (EX  v : val,
          address_mapsto m0 v (Share.unrel Share.Lsh sh)
            (Share.unrel Share.Rsh sh) (b0, Int.unsigned i0))).
    - apply sepcon_derives; apply orp_left.
      * apply andp_left2, (exp_right v1).
        auto.
      * apply andp_left2; auto.
      * apply andp_left2, (exp_right v2).
        auto.
      * apply andp_left2; auto.
    - clear v1 v2.
      rewrite exp_sepcon1.
      apply exp_left; intro v1.
      rewrite exp_sepcon2.
      apply exp_left; intro v2.
      clear H H1; rename H0 into H.
      destruct H as [? [? [? [? ?]]]].
      inversion H; subst.
      inversion H0; subst.
      erewrite !size_chunk_sizeof in H1 by eauto.
      apply address_mapsto_overlap; auto.
  + rewrite sepcon_andp_prop1, sepcon_andp_prop2.
    apply andp_left2, andp_left2.
    apply nonlock_permission_bytes_overlap; auto.
    clear H H1; rename H0 into H.
    erewrite !size_chunk_sizeof in H by eauto.
    destruct H as [? [? [? [? ?]]]].
    inversion H; subst.
    inversion H0; subst.
    auto.
Qed.

Lemma memory_block_overlap: forall sh p1 n1 p2 n2, nonunit sh -> pointer_range_overlap p1 n1 p2 n2 -> memory_block sh n1 p1 * memory_block sh n2 p2 |-- FF.
Proof.
  intros.
  unfold memory_block.
  destruct p1; try solve [rewrite FF_sepcon; auto].
  destruct p2; try solve [rewrite normalize.sepcon_FF; auto].
  rewrite sepcon_andp_prop1.
  rewrite sepcon_andp_prop2.
  apply normalize.derives_extract_prop; intros.
  apply normalize.derives_extract_prop; intros.
  rewrite memory_block'_eq; [| pose proof Int.unsigned_range i; omega | apply Clight_lemmas.Nat2Z_add_le; auto].
  rewrite memory_block'_eq; [| pose proof Int.unsigned_range i0; omega | apply Clight_lemmas.Nat2Z_add_le; auto].
  unfold memory_block'_alt.
  if_tac.
  + clear H2.
    apply VALspec_range_overlap.
    pose proof pointer_range_overlap_non_zero _ _ _ _ H0.
    rewrite !Coqlib.nat_of_Z_eq by omega.
    destruct H0 as [[? ?] [[? ?] [? [? ?]]]].
    inversion H0; inversion H4.
    subst.
    auto.
  + apply nonlock_permission_bytes_overlap; auto.
    pose proof pointer_range_overlap_non_zero _ _ _ _ H0.
    rewrite !Coqlib.nat_of_Z_eq by omega.
    destruct H0 as [[? ?] [[? ?] [? [? ?]]]].
    inversion H0; inversion H5.
    subst.
    auto.
Qed.

Lemma mapsto_conflict:
  forall sh t v v2 v3,
  nonunit sh ->
  mapsto sh t v v2 * mapsto sh t v v3 |-- FF.
Proof.
  intros.
  rewrite (@add_andp (pred rmap) (algNatDed _) _ _ (mapsto_pure_facts sh t v v3)).
  simpl.
  rewrite andp_comm.
  rewrite sepcon_andp_prop.
  apply prop_andp_left; intros [[? ?] ?].
  unfold mapsto.
  rewrite H0.
  destruct (type_is_volatile t); try (rewrite FF_sepcon; auto).
  destruct v; try (rewrite FF_sepcon; auto).
  pose proof (size_chunk_pos x).
  if_tac.
*  
  normalize.
  rewrite distrib_orp_sepcon, !distrib_orp_sepcon2;
  repeat apply orp_left;
  rewrite ?sepcon_andp_prop1;  repeat (apply prop_andp_left; intro);
  rewrite ?sepcon_andp_prop2;  repeat (apply prop_andp_left; intro);
  rewrite ?exp_sepcon1;  repeat (apply exp_left; intro);
  rewrite ?exp_sepcon2;  repeat (apply exp_left; intro);
  apply address_mapsto_overlap;
  exists (b, Int.unsigned i); repeat split; omega.
*
  rewrite ?sepcon_andp_prop1;  repeat (apply prop_andp_left; intro);
  rewrite ?sepcon_andp_prop2;  repeat (apply prop_andp_left; intro).
  apply nonlock_permission_bytes_overlap; auto.
  exists (b, Int.unsigned i); repeat split; omega.
Qed.

Lemma memory_block_conflict: forall sh n m p,
  nonunit sh ->
  0 < n <= Int.max_unsigned -> 0 < m <= Int.max_unsigned ->
  memory_block sh n p * memory_block sh m p |-- FF.
Proof.
  intros.
  unfold memory_block.
  destruct p; try solve [rewrite FF_sepcon; auto].
  rewrite sepcon_andp_prop1.
  apply prop_andp_left; intro.
  rewrite sepcon_comm.
  rewrite sepcon_andp_prop1.
  apply prop_andp_left; intro.
  rewrite memory_block'_eq; [| pose proof Int.unsigned_range i; omega | rewrite Z2Nat.id; omega].
  rewrite memory_block'_eq; [| pose proof Int.unsigned_range i; omega | rewrite Z2Nat.id; omega].
  unfold memory_block'_alt.
  if_tac.
  + apply VALspec_range_overlap.
    exists (b, Int.unsigned i).
    simpl; repeat split; auto; try omega;
    rewrite Z2Nat.id; omega.
  + apply nonlock_permission_bytes_overlap; auto.
    exists (b, Int.unsigned i).
    repeat split; auto; try rewrite Z2Nat.id; omega.
Qed.

Lemma memory_block_non_pos_Vptr: forall sh n b z, n <= 0 -> memory_block sh n (Vptr b z) = emp.
Proof.
  intros. unfold memory_block.
  replace (nat_of_Z n) with (0%nat) by (symmetry; apply nat_of_Z_neg; auto).
  unfold memory_block'.
  pose proof Int.unsigned_range z.
  assert (Int.unsigned z + n <= Int.modulus) by omega.
  apply pred_ext; normalize.
  apply andp_right; auto.
  intros ? _; simpl; auto.
Qed.

Lemma memory_block_zero_Vptr: forall sh b z, memory_block sh 0 (Vptr b z) = emp.
Proof.
  intros; apply memory_block_non_pos_Vptr.
  omega.
Qed.

Lemma mapsto_zeros_memory_block: forall sh n b ofs,
  0 <= n < Int.modulus ->
  Int.unsigned ofs+n <= Int.modulus ->
  readable_share sh ->
  mapsto_zeros n sh (Vptr b ofs) |--
  memory_block sh n (Vptr b ofs).
Proof.
  unfold mapsto_zeros.
  intros.
  rename H0 into H'. rename H1 into RS.
  unfold memory_block.
  repeat rewrite Int.unsigned_repr by omega.
  apply andp_right.
  + intros ? _; auto.
  + rewrite <- (Z2Nat.id n) in H' by omega.
    rewrite <- (Z2Nat.id n) in H by omega.
    change nat_of_Z with Z.to_nat.
    forget (Z.to_nat n) as n'.
    clear n.
    remember (Int.unsigned ofs) as ofs'.
    assert (Int.unsigned (Int.repr ofs') = ofs')
      by (subst; rewrite Int.repr_unsigned; reflexivity).
    assert (0 <= ofs' /\ ofs' + Z.of_nat n' <= Int.modulus).
    Focus 1. {
      pose proof Int.unsigned_range ofs.
      omega.
    } Unfocus.
    clear Heqofs' H'.
    assert (Int.unsigned (Int.repr ofs') = ofs' \/ n' = 0%nat) by tauto.
    clear H0; rename H2 into H0.
    revert ofs' H H1 H0; induction n'; intros.
    - simpl; auto.
    - destruct H1.
      rewrite inj_S in H2. unfold Z.succ in H2. simpl.
      apply sepcon_derives; auto.
      * unfold mapsto_, mapsto. simpl.
        rewrite if_true by auto.
        apply orp_right2.
        rewrite prop_true_andp by auto.
        apply exp_right with (Vint Int.zero).
        destruct H0; [| omega].
        rewrite H0.
        auto.
      * fold address_mapsto_zeros. fold memory_block'.
        apply IHn'. omega. omega.
        destruct (zlt (ofs' + 1) Int.modulus).
        1: rewrite Int.unsigned_repr; [left; reflexivity | unfold Int.max_unsigned; omega].
        1: right.
           destruct H0; [| inversion H0].
           omega.
Qed.

Lemma memory_block'_split:
  forall sh b ofs i j,
   0 <= i <= j ->
    j <= j+ofs <= Int.modulus ->
   memory_block' sh (nat_of_Z j) b ofs = 
      memory_block' sh (nat_of_Z i) b ofs * memory_block' sh (nat_of_Z (j-i)) b (ofs+i).
Proof.
  intros.
  rewrite memory_block'_eq; try rewrite Coqlib.nat_of_Z_eq; try omega.
  rewrite memory_block'_eq; try rewrite Coqlib.nat_of_Z_eq; try omega.
  rewrite memory_block'_eq; try rewrite Coqlib.nat_of_Z_eq; try omega.
  unfold memory_block'_alt.
  repeat (rewrite Coqlib.nat_of_Z_eq; try omega).
  if_tac.
  + etransitivity ; [ | eapply VALspec_range_split2; [reflexivity | omega | omega]].
    f_equal.
    omega.
  + apply nonlock_permission_bytes_split2; omega.
Qed.

Lemma memory_block_split:
  forall (sh : share) (b : block) (ofs n m : Z),
  0 <= n ->
  0 <= m ->
  n + m < Int.modulus ->
  n + m <= n + m + ofs <= Int.modulus ->
  memory_block sh (n + m) (Vptr b (Int.repr ofs)) =
  memory_block sh n (Vptr b (Int.repr ofs)) *
  memory_block sh m (Vptr b (Int.repr (ofs + n))).
Proof.
  intros.
  unfold memory_block.
  rewrite memory_block'_split with (i := n); [| omega |].
  Focus 2. {
    pose proof Int.unsigned_range (Int.repr ofs).
    pose proof Int.unsigned_repr_eq ofs.
    assert (ofs mod Int.modulus <= ofs) by (apply Z.mod_le; omega).
    omega.
  } Unfocus.
  replace (n + m - n) with m by omega.
  replace (memory_block' sh (nat_of_Z m) b (Int.unsigned (Int.repr ofs) + n)) with
    (memory_block' sh (nat_of_Z m) b (Int.unsigned (Int.repr (ofs + n)))).
  Focus 2. {
    destruct (zeq m 0).
    + subst. reflexivity.
    + assert (ofs + n < Int.modulus) by omega.
      rewrite !Int.unsigned_repr by (unfold Int.max_unsigned; omega).
      reflexivity.
  } Unfocus.
  apply pred_ext.
  + apply prop_andp_left; intros.
    apply sepcon_derives; (apply andp_right; [intros ? _; simpl | apply derives_refl]).
    - omega.
    - rewrite Int.unsigned_repr_eq.
      assert ((ofs + n) mod Int.modulus <= ofs + n) by (apply Z.mod_le; omega).
      omega.
  + apply andp_right; [intros ? _; simpl |].
    - rewrite Int.unsigned_repr_eq.
      assert (ofs mod Int.modulus <= ofs) by (apply Z.mod_le; omega).
      omega.
    - apply sepcon_derives; apply andp_left2; apply derives_refl.
Qed.

Lemma memory_block_share_join:
  forall sh1 sh2 sh n p,
   sepalg.join sh1 sh2 sh ->
   memory_block sh1 n p * memory_block sh2 n p = memory_block sh n p.
Proof.
  intros.
  destruct p; try solve [unfold memory_block; rewrite FF_sepcon; auto].
  destruct (zle 0 n).
  Focus 2. {
    rewrite !memory_block_non_pos_Vptr by omega.
    rewrite emp_sepcon; auto.
  } Unfocus.
  unfold memory_block.
  destruct (zle (Int.unsigned i + n) Int.modulus).
  + rewrite !prop_true_andp by auto.
    repeat (rewrite memory_block'_eq; [| pose proof Int.unsigned_range i; omega | rewrite Coqlib.nat_of_Z_eq; omega]).
    unfold memory_block'_alt.
    destruct (readable_share_dec sh1), (readable_share_dec sh2).
    - rewrite if_true by (eapply readable_share_join; eauto).
      apply VALspec_range_share_join.
      * apply readable_share_unrel_Rsh; auto.
      * apply readable_share_unrel_Rsh; auto.
      * apply Share.unrel_join; auto.
      * apply Share.unrel_join; auto.
    - rewrite if_true by (eapply readable_share_join; eauto).
      rewrite sepcon_comm.
      rewrite <- (splice_unrel_unrel sh2).
      replace (Share.unrel Share.Rsh sh) with (Share.unrel Share.Rsh sh1).
      replace (Share.unrel Share.Rsh sh2) with Share.bot.
      apply nonlock_permission_bytes_VALspec_range_join.
      * apply Share.unrel_join; auto.
      * rewrite readable_share_unrel_Rsh in n0.
        symmetry; apply not_nonunit_bot; auto.
      * rewrite readable_share_unrel_Rsh in n0.
        apply not_nonunit_bot in n0.
        rewrite <- (splice_unrel_unrel sh1), <- (splice_unrel_unrel sh).
        rewrite !Share.unrel_splice_R.
        apply Share.unrel_join with (x := Share.Rsh) in H.
        rewrite n0 in H.
        eapply join_eq; eauto.
    - rewrite if_true by (eapply readable_share_join; eauto).
      rewrite <- (splice_unrel_unrel sh1).
      replace (Share.unrel Share.Rsh sh) with (Share.unrel Share.Rsh sh2).
      replace (Share.unrel Share.Rsh sh1) with Share.bot.
      apply nonlock_permission_bytes_VALspec_range_join.
      * apply Share.unrel_join; auto.
      * rewrite readable_share_unrel_Rsh in n0.
        symmetry; apply not_nonunit_bot; auto.
      * rewrite readable_share_unrel_Rsh in n0.
        apply not_nonunit_bot in n0.
        rewrite <- (splice_unrel_unrel sh2), <- (splice_unrel_unrel sh).
        rewrite !Share.unrel_splice_R.
        apply Share.unrel_join with (x := Share.Rsh) in H.
        rewrite n0 in H.
        eapply join_eq; eauto.
    - rewrite if_false.
      * apply nonlock_permission_bytes_share_join; auto.
      * rewrite readable_share_unrel_Rsh in *.
        apply not_nonunit_bot in n0.
        apply not_nonunit_bot in n1.
        apply Share.unrel_join with (x := Share.Rsh) in H.
        rewrite n0, n1 in H.
        rewrite (@not_nonunit_bot (Share.unrel Share.Rsh sh)).
        eapply join_eq; eauto.
  + rewrite !prop_false_andp by auto.
    rewrite FF_sepcon; auto.
Qed.

Lemma mapsto_pointer_void:
  forall sh t a, mapsto sh (Tpointer t a) = mapsto sh (Tpointer Tvoid a).
Proof.
intros.
unfold mapsto.
extensionality v1 v2.
simpl. auto.
Qed.

Lemma mapsto_unsigned_signed:
 forall sign1 sign2 sh sz v i,
  mapsto sh (Tint sz sign1 noattr) v (Vint (Cop.cast_int_int sz sign1 i)) =
  mapsto sh (Tint sz sign2 noattr) v (Vint (Cop.cast_int_int sz sign2 i)).
Proof.
 intros.
 unfold mapsto.
 unfold address_mapsto, res_predicates.address_mapsto.
 simpl.
 destruct sz; auto;
 destruct sign1, sign2; auto;
 destruct v; auto; simpl Cop.cast_int_int;
 repeat rewrite (prop_true_andp (_ <= _ <= _)) by
  first [ apply (expr_lemmas3.sign_ext_range' 8 i); compute; split; congruence
          | apply (expr_lemmas3.sign_ext_range' 16 i); compute; split; congruence
          ];
 repeat rewrite (prop_true_andp (_ <= _)) by
  first [ apply (expr_lemmas3.zero_ext_range' 8 i); compute; split; congruence
          | apply (expr_lemmas3.zero_ext_range' 16 i); compute; split; congruence
          ];
 simpl;
 repeat rewrite (prop_true_andp True) by auto;
 repeat rewrite (prop_false_andp  (Vint _ = Vundef) ) by (intro; discriminate);
 cbv beta;
 repeat first [rewrite @FF_orp | rewrite @orp_FF].
*
 f_equal. if_tac; clear H.
 Focus 2. {
   f_equal.
   apply pred_ext; intros ?; hnf; simpl;
   intros; (split; [| tauto]).
   + intros _.
     simpl.
     destruct (zero_ext_range' 8 i); [split; cbv; intros; congruence |].
     exact H1.
   + intros _.
     simpl.
     destruct (sign_ext_range' 8 i); [split; cbv; intros; congruence |].
     exact (conj H0 H1).
 } Unfocus.
 f_equal. f_equal; extensionality bl.
 f_equal. f_equal.
 simpl;  apply prop_ext; intuition.
 destruct bl; inv H0. destruct bl; inv H.
 unfold Memdata.decode_val in *. simpl in *.
 destruct m; try congruence.
 unfold Memdata.decode_int in *.
 rewrite rev_if_be_1 in *. simpl in *.
 apply Vint_inj in H1. f_equal.
 rewrite <- (Int.zero_ext_sign_ext _ (Int.repr _)) by omega.
  rewrite <- (Int.zero_ext_sign_ext _ i) by omega.
 f_equal; auto.
 inv H3.
 destruct bl; inv H0. destruct bl; inv H3.
 unfold Memdata.decode_val in *. simpl in *.
 destruct m; try congruence.
 unfold Memdata.decode_int in *.
 rewrite rev_if_be_1 in *. simpl in *.
 apply Vint_inj in H. f_equal.
 rewrite <- (Int.sign_ext_zero_ext _ (Int.repr _)) by omega.
 rewrite <- (Int.sign_ext_zero_ext _ i) by omega.
 f_equal; auto.
*
 f_equal.
 if_tac; clear H.
 Focus 2. {
   f_equal.
   apply pred_ext; intros ?; hnf; simpl;
   intros; (split; [| tauto]).
   + intros _.
     simpl.
     destruct (sign_ext_range' 8 i); [split; cbv; intros; congruence |].
     exact (conj H0 H1).
   + intros _.
     simpl.
     destruct (zero_ext_range' 8 i); [split; cbv; intros; congruence |].
     exact H1.
 } Unfocus.
 f_equal; f_equal; extensionality bl.
 f_equal. f_equal.
 simpl;  apply prop_ext; intuition.
 destruct bl; inv H0. destruct bl; inv H3.
 unfold Memdata.decode_val in *. simpl in *.
 destruct m; try congruence.
 unfold Memdata.decode_int in *.
 rewrite rev_if_be_1 in *. simpl in *.
 apply Vint_inj in H. f_equal.
 rewrite <- (Int.sign_ext_zero_ext _ (Int.repr _)) by omega.
 rewrite <- (Int.sign_ext_zero_ext _ i) by omega.
 f_equal; auto.
 destruct bl; inv H0. destruct bl; inv H3.
 unfold Memdata.decode_val in *. simpl in *.
 destruct m; try congruence.
 unfold Memdata.decode_int in *.
 rewrite rev_if_be_1 in *. simpl in *.
 apply Vint_inj in H. f_equal.
 rewrite <- (Int.zero_ext_sign_ext _ (Int.repr _)) by omega.
  rewrite <- (Int.zero_ext_sign_ext _ i) by omega.
 f_equal; auto.
*
 f_equal.
  if_tac; [| auto]; clear H.
 Focus 2. {
   f_equal.
   apply pred_ext; intros ?; hnf; simpl;
   intros; (split; [| tauto]).
   + intros _.
     simpl.
     destruct (zero_ext_range' 16 i); [split; cbv; intros; congruence |].
     exact H1.
   + intros _.
     simpl.
     destruct (sign_ext_range' 16 i); [split; cbv; intros; congruence |].
     exact (conj H0 H1).
 } Unfocus.
  f_equal; f_equal; extensionality bl.
 f_equal. f_equal.
 simpl;  apply prop_ext; intuition.
 destruct bl; inv H0. destruct bl; inv H3. destruct bl; inv H1.
 unfold Memdata.decode_val in *. simpl in *.
 destruct m; try congruence.
 destruct m0; try congruence.
 unfold Memdata.decode_int in *.
 apply Vint_inj in H. f_equal.
 rewrite <- (Int.zero_ext_sign_ext _ (Int.repr _)) by omega.
  rewrite <- (Int.zero_ext_sign_ext _ i) by omega.
 f_equal; auto.
 destruct bl; inv H0. destruct bl; inv H3. destruct bl; inv H1.
 unfold Memdata.decode_val in *. simpl in *.
 destruct m; try congruence.
 destruct m0; try congruence.
 unfold Memdata.decode_int in *.
 apply Vint_inj in H. f_equal.
 rewrite <- (Int.sign_ext_zero_ext _ (Int.repr _)) by omega.
 rewrite <- (Int.sign_ext_zero_ext _ i) by omega.
 f_equal; auto.
*
 f_equal.
  if_tac; [| auto]; clear H.
 Focus 2. {
   f_equal.
   apply pred_ext; intros ?; hnf; simpl;
   intros; (split; [| tauto]).
   + intros _.
     simpl.
     destruct (sign_ext_range' 16 i); [split; cbv; intros; congruence |].
     exact (conj H0 H1).
   + intros _.
     simpl.
     destruct (zero_ext_range' 16 i); [split; cbv; intros; congruence |].
     exact H1.
 } Unfocus.
 f_equal; f_equal; extensionality bl.
 f_equal. f_equal.
 simpl;  apply prop_ext; intuition.
 destruct bl; inv H0. destruct bl; inv H3. destruct bl; inv H1.
 unfold Memdata.decode_val in *. simpl in *.
 destruct m; try congruence.
 destruct m0; try congruence.
 unfold Memdata.decode_int in *.
 apply Vint_inj in H. f_equal.
 rewrite <- (Int.sign_ext_zero_ext _ (Int.repr _)) by omega.
 rewrite <- (Int.sign_ext_zero_ext _ i) by omega.
 f_equal; auto.
 destruct bl; inv H0. destruct bl; inv H3. destruct bl; inv H1.
 unfold Memdata.decode_val in *. simpl in *.
 destruct m; try congruence.
 destruct m0; try congruence.
 unfold Memdata.decode_int in *.
 apply Vint_inj in H. f_equal.
 rewrite <- (Int.zero_ext_sign_ext _ (Int.repr _)) by omega.
  rewrite <- (Int.zero_ext_sign_ext _ i) by omega.
 f_equal; auto.
Qed.

Lemma mapsto_tuint_tint:
  forall sh, mapsto sh tuint = mapsto sh tint.
Proof.
intros.
extensionality v1 v2.
reflexivity.
Qed.

Lemma mapsto_tuint_tptr_nullval:
  forall sh p t, mapsto sh (Tpointer t noattr) p nullval = mapsto sh tuint p nullval.
Proof.
intros.
unfold mapsto.
simpl.
destruct p; simpl; auto.
if_tac; simpl; auto.
rewrite !prop_true_andp by auto.
rewrite (prop_true_andp True) by auto.
reflexivity.
f_equal. f_equal. f_equal.
unfold tc_val'.
apply prop_ext; intuition; hnf; auto.
Qed.

Definition is_int32_noattr_type t :=
 match t with
 | Tint I32 _ {| attr_volatile := false; attr_alignas := None |} => True
 | _ => False
 end.

Lemma mapsto_mapsto_int32:
  forall sh t1 t2 p v,
   is_int32_noattr_type t1 ->
   is_int32_noattr_type t2 ->
   mapsto sh t1 p v |-- mapsto sh t2 p v.
Proof.
intros.
destruct t1; try destruct i; try contradiction.
destruct a as [ [ | ] [ | ] ]; try contradiction.
destruct t2; try destruct i; try contradiction.
destruct a as [ [ | ] [ | ] ]; try contradiction.
apply derives_refl.
Qed.

Lemma mapsto_mapsto__int32:
  forall sh t1 t2 p v,
   is_int32_noattr_type t1 ->
   is_int32_noattr_type t2 ->
   mapsto sh t1 p v |-- mapsto_ sh t2 p.
Proof.
intros.
destruct t1; try destruct i; try contradiction.
destruct a as [ [ | ] [ | ] ]; try contradiction.
destruct t2; try destruct i; try contradiction.
destruct a as [ [ | ] [ | ] ]; try contradiction.
fold noattr.
unfold mapsto_.
destruct s,s0; fold tuint; fold tint; 
  repeat rewrite mapsto_tuint_tint;
  try apply mapsto_mapsto_.
Qed.

Lemma mapsto_null_mapsto_pointer:
  forall t sh v, 
             mapsto sh tint v nullval = 
             mapsto sh (tptr t) v nullval.
Proof.
  intros.
  unfold mapsto.
  simpl.
  destruct v; auto. f_equal; auto.
  if_tac.
  + f_equal. f_equal. apply pred_ext; unfold derives; simpl; tauto.
  + f_equal. apply pred_ext; unfold derives; simpl;
    unfold tc_val', tc_val, tptr, tint, nullval; simpl;
    tauto.
Qed.
