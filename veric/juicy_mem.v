Require Import veric.juicy_base.
Require Import veric.shares.
Import cjoins.

Definition perm_of_sh (rsh sh: Share.t): option permission :=
  if eq_dec sh Share.top 
    then if eq_dec rsh Share.top 
            then Some Freeable
            else Some Writable
    else if eq_dec sh Share.bot 
           then if eq_dec rsh Share.bot
                   then None
                   else Some Nonempty
           else Some Readable.

Definition contents_at (m: mem) (loc: address) : memval := 
  ZMap.get (snd loc) (PMap.get (fst loc) (mem_contents m)).

Definition contents_cohere (m: mem) (phi: rmap) := 
  forall rsh sh v loc pp, phi @ loc = YES rsh sh (VAL v) pp -> contents_at m loc = v /\ pp=NoneP.

Definition valshare (r: resource) : share :=
    match r with
      | YES rsh sh _ _ => pshare_sh sh
      | _ => Share.bot
    end.


Definition res_retain' (r: resource) : Share.t :=
 match r with
  | NO sh => sh
  | YES sh _ _ _ => sh
  | PURE _ _ => Share.top
 end.

Definition perm_of_res (r: resource) := 
  (*  perm_of_sh (res_retain' r) (valshare r). *)
 match r with
 | NO sh => if eq_dec sh Share.bot then None else Some Nonempty
 | PURE _ _ => Some Nonempty
 | YES rsh sh (VAL _) _ => perm_of_sh rsh (pshare_sh sh)
 | YES rsh sh _ _ => Some Nonempty
 end.

Definition access_cohere (m: mem)  (phi: rmap) :=
  forall loc,  access_at m loc Cur = perm_of_res (phi @ loc).

Definition max_access_at m loc := access_at m loc Max.

Definition max_access_cohere (m: mem) (phi: rmap)  :=
 forall loc,
   match phi @ loc with
   | YES rsh sh (VAL _) _ => perm_order'' (max_access_at m loc) (perm_of_sh rsh (pshare_sh sh))
   | YES rsh sh _ _ => (fst loc < nextblock m)%positive
   | NO rsh => perm_order'' (max_access_at m loc) (perm_of_sh rsh Share.bot )
   | PURE _ _ => (fst loc < nextblock m)%positive
  end.

Definition alloc_cohere (m: mem) (phi: rmap) :=
 forall loc,  (fst loc >= nextblock m)%positive -> phi @ loc = NO Share.bot.

Inductive juicy_mem: Type :=
  mkJuicyMem: forall (m: mem) (phi: rmap) 
    (JMcontents: contents_cohere m phi)
    (JMaccess: access_cohere m phi)
    (JMmax_access: max_access_cohere m phi)
    (JMalloc: alloc_cohere m phi),
       juicy_mem.

Section selectors.
Variable (j: juicy_mem).
Definition m_dry := match j with mkJuicyMem m _ _ _ _ _ => m end.
Definition m_phi := match j with mkJuicyMem _ phi _ _ _ _ => phi end.
Lemma juicy_mem_contents: contents_cohere m_dry m_phi.
Proof. unfold m_dry, m_phi; destruct j; auto. Qed.
Lemma juicy_mem_access: access_cohere m_dry m_phi.
Proof. unfold m_dry, m_phi; destruct j; auto. Qed.
Lemma juicy_mem_max_access: max_access_cohere m_dry m_phi.
Proof. unfold m_dry, m_phi; destruct j; auto. Qed.
Lemma juicy_mem_alloc_cohere: alloc_cohere m_dry m_phi.
Proof. unfold m_dry, m_phi; destruct j; auto. Qed.
End selectors.

Lemma perm_of_empty_inv {s t} : perm_of_sh s t = None -> s = Share.bot /\ t = Share.bot.
Proof.
intros.
unfold perm_of_sh in*.
if_tac in H; subst; auto.
if_tac in H; subst; auto.
inv H. inv H.
if_tac in H; subst; auto.
if_tac in H; subst; auto. inv H. inv H.
Qed.

Lemma writable_join_sub: forall loc phi1 phi2, 
  join_sub phi1 phi2 -> writable loc phi1 -> writable loc phi2.
Proof.
intros.
hnf in H0|-*.
destruct H; generalize (resource_at_join _ _ _ loc H); clear H.
revert H0; destruct (phi1 @ loc); intros; try contradiction.
destruct H0; subst.
inv H; try pfullshare_join. simpl.
split; auto.
Qed.

Lemma writable_inv: forall phi loc, writable loc phi ->
  exists rsh, exists k, exists pp, phi @ loc = YES rsh pfullshare k pp /\ isVAL k.
Proof.
simpl.
intros phi loc H.
destruct (phi @ loc); try solve [inversion H].
destruct H.
destruct k; solve [
    rewrite H; repeat eexists; eauto
  | inversion H0 as [? H1]; inv H1].
Qed.

Lemma nreadable_inv: forall phi loc, ~readable loc phi 
  -> (exists rsh, phi @ loc = NO rsh)
   \/ (exists rsh, exists sh, exists k, exists pp, phi @ loc = YES rsh sh k pp /\ ~isVAL k)
   \/ (exists k, exists pp, phi @ loc = PURE k pp).
Proof.
intros.
unfold readable in H.
simpl in H.
destruct (phi@loc); eauto 50.
Qed.

Lemma VAL_valid:
 forall (f: address -> option (pshare*kind)),
   (forall l sh k, f l = Some (sh,k) -> isVAL k) ->
   AV.valid f.
Proof.
intros.
intros b ofs.
case_eq (f (b,ofs)); intros; auto.
destruct p.
specialize (H _ _ _ H0).
destruct k; solve [
    auto
  | inversion H ].
Qed.

Lemma age1_joinx {A}  {JA: Join A}{PA: Perm_alg A}{agA: ageable A}{AgeA: Age_alg A} : forall phi1 phi2 phi3 phi1' phi2' phi3',
             age phi1 phi1' -> age phi2 phi2' -> age phi3 phi3' ->
             join phi1 phi2 phi3 -> join phi1' phi2' phi3'.
Proof.
intros.
destruct (age1_join _ H2 H) as [phi2'' [phi3'' [? [? ?]]]].
unfold age in *.
congruence.
Qed.

Lemma constructive_age1_join  {A}  {JA: Join A}{PA: Perm_alg A}{agA: ageable A}{AgeA: Age_alg A} : forall x y z x' : A,
       join x y z ->
       age x x' ->
       { yz' : A*A | join x' (fst yz') (snd yz') /\ age y (fst yz') /\ age z (snd yz')}.
Proof.
pose proof I.
intros.
case_eq (age1 y); [intros y' ? | intros].
case_eq (age1 z); [intros z' ? | intros].
exists (y',z').
simpl.
split; auto.
apply (age1_joinx x y z x' y' z' H1 H2 H3 H0).
elimtype False.
destruct (age1_join _ H0 H1) as [? [? [? [? ?]]]].
unfold age in *.
congruence.
elimtype False.
destruct (age1_join _ H0 H1) as [? [? [? [? ?]]]].
unfold age in *.
congruence.
Qed.
          
Lemma age1_constructive_joins_eq : forall {A}  {JA: Join A}{PA: Perm_alg A}{agA: ageable A}{AgeA: Age_alg A}  {phi1 phi2},
  constructive_joins phi1 phi2 
  -> forall {phi1'}, age1 phi1 = Some phi1' 
  -> forall {phi2'}, age1 phi2 = Some phi2' 
  -> constructive_joins phi1' phi2'.
Proof.
intros.
destruct X as [? ?H].
destruct (constructive_age1_join _ _ _ _ H1 H) as [[y z] [? [? ?]]].
simpl in *.
unfold age in H3. rewrite H0 in H3; inv H3; econstructor; eauto.
Qed.


Program Definition age1_juicy_mem (j: juicy_mem): option juicy_mem :=
      match age1 (m_phi j) with
        | Some phi' => Some (mkJuicyMem (m_dry j) phi' _ _ _ _)
        | None => None
      end.
Next Obligation.  (* contents_cohere *)
 assert (necR (m_phi j) phi') 
   by (constructor 1; symmetry in Heq_anonymous; apply Heq_anonymous).
 destruct j; hnf; simpl in *; intros.
 case_eq (phi @ loc); intros.
 apply (necR_NO _ _ _ _ H) in H1. congruence.
 generalize (necR_YES _ _ _ _ _ _ _ H H1); intros.
 rewrite H0 in H2. inv H2.
 destruct (JMcontents t p v loc _ H1). subst; split; auto.
 apply preds_fmap_NoneP.
 rewrite (necR_PURE _ _ _ _ _ H H1) in H0. inv H0.
Qed.
Next Obligation. (* access_cohere *)
 assert (necR (m_phi j) phi') 
   by (constructor 1; symmetry in Heq_anonymous; apply Heq_anonymous).
 destruct j; hnf; simpl in *; intros.
 generalize (JMaccess loc); case_eq (phi @ loc); intros.
 apply (necR_NO _ _ loc _ H) in H0. rewrite H0; auto.
 rewrite (necR_YES _ _ _ _ _ _ _ H H0); auto.
 rewrite (necR_PURE _ _ _ _ _ H H0); auto.
Qed.
Next Obligation. (* max_access_cohere *)
 assert (necR (m_phi j) phi') 
   by (constructor 1; symmetry in Heq_anonymous; apply Heq_anonymous).
 destruct j; hnf; simpl in *; intros.
 generalize (JMmax_access loc); case_eq (phi @ loc); intros.
 apply (necR_NO _ _ loc _ H) in H0. rewrite H0; auto.
 rewrite (necR_YES _ _ _ _ _ _ _ H H0); auto.
 rewrite (necR_PURE _ _ _ _ _ H H0); auto.
Qed.
Next Obligation. (* alloc_cohere *)
 assert (necR (m_phi j) phi') 
   by (constructor 1; symmetry in Heq_anonymous; apply Heq_anonymous).
 destruct j; hnf; simpl in *; intros.
 specialize (JMalloc loc H0).
 apply (necR_NO _ _ loc _ H). auto.
Qed.

Lemma age1_juicy_mem_unpack: forall j j', 
  age1_juicy_mem j = Some j' ->
  age (m_phi j)  (m_phi j') 
  /\ m_dry j = m_dry j'.
Proof.
intros.
unfold age1_juicy_mem in H.
invSome.
inv H.
split; simpl; auto.
symmetry in H0; apply H0.
Qed.

Lemma age1_juicy_mem_unpack': forall j j',
  age (m_phi j)  (m_phi j')  /\ m_dry j = m_dry j' ->
  age1_juicy_mem j = Some j'.
Proof.
  intuition.
  unfold age1_juicy_mem.
  generalize (eq_refl (age1 (m_phi j))).
  pattern (age1 (m_phi j)) at 1 3.
  rewrite H0;  clear H0. intros H0.
  f_equal.
  destruct j, j'; simpl in *; subst; repeat f_equal; try apply proof_irr.
Qed.  

Lemma age1_juicy_mem_unpack'': forall j j',
  age (m_phi j)  (m_phi j')  -> m_dry j = m_dry j' ->
  age1_juicy_mem j = Some j'.
Proof.
  intros.
  apply age1_juicy_mem_unpack'.
 split; auto.
Qed.

(* TODO: move into rmaps_lemmas *)
Lemma rmap_join_eq_level: forall phi1 phi2: rmap, joins phi1 phi2 -> level phi1 = level phi2.
Proof.
intros until phi2; intro H.
destruct H as [? H].
apply join_level in H; destruct H; congruence.
Qed.

Lemma rmap_join_sub_eq_level: forall phi1 phi2: rmap, 
          join_sub phi1 phi2 -> level phi1 = level phi2.
Proof.
intros until phi2; intro H.
destruct H; apply join_level in H; destruct H; congruence.
Qed.

Lemma age1_juicy_mem_None1:
  forall j, age1_juicy_mem j = None -> age1 (m_phi j) = None.
Proof.
intros j H.
destruct j.
simpl.
unfold age1_juicy_mem in H; simpl in H.
revert H; generalize (refl_equal (age1 phi)); pattern (age1 phi) at 1 3; destruct (age1 phi); intros; auto.
inv H.
Qed.

Lemma age1_juicy_mem_None2:
  forall j, age1 (m_phi j) = None -> age1_juicy_mem j = None.
Proof.
intros.
unfold age1_juicy_mem.
generalize (eq_refl (age1 (m_phi j))).
pattern (age1 (m_phi j)) at 1 3.
rewrite H.
auto.
Qed.

Lemma age1_juicy_mem_Some:
  forall j j', age1_juicy_mem j = Some j' -> age1 (m_phi j) = Some (m_phi j').
Proof.
intros.
apply age1_juicy_mem_unpack in H; intuition.
Qed.


Lemma unage_juicy_mem: forall j' : juicy_mem,
   exists j : juicy_mem, age1_juicy_mem j = Some j'.
Proof.
intros.
destruct j' as [m phi'].
destruct (af_unage age_facts phi') as [phi ?].
assert (NEC: necR phi phi')  by (constructor 1; auto).
 rename H into Hage.
assert (contents_cohere m phi).
  hnf; intros.
  generalize (necR_YES phi phi' loc rsh sh (VAL v) pp NEC H); intro.
  destruct (JMcontents _ _ _ _ _ H0).
  rewrite H2 in H0.
  split; auto.
  generalize (necR_YES' _ _ loc rsh sh (VAL v) NEC); intro.
  apply H3 in H0. congruence.
assert (access_cohere m phi). 
  hnf; intros.
  generalize (JMaccess loc); intros.
  case_eq (phi @ loc); intros.
  apply (necR_NO _ _ loc _ NEC) in H1. rewrite H1 in H0; auto.
  apply (necR_YES _ _ _ _ _ _ _ NEC) in H1. rewrite H1 in H0; auto.
  apply (necR_PURE _ _ _ _ _ NEC) in H1. rewrite H1 in H0; auto.
assert (max_access_cohere m phi). 
  hnf; intros.
  generalize (JMmax_access loc); intros.
  case_eq (phi @ loc); intros.
  apply (necR_NO _ _ _ _ NEC) in H2; rewrite H2 in H1; auto.
  rewrite (necR_YES _ _ _ _ _ _ _ NEC H2) in H1; auto.
  rewrite (necR_PURE _ _ _ _ _ NEC H2) in H1; auto.
assert (alloc_cohere m phi).
  hnf; intros.
  generalize (JMalloc loc H2); intros.
  case_eq (phi @ loc); intros.
  apply (necR_NO _ _ _ _ NEC) in H4; rewrite H4 in H3; auto.
  rewrite (necR_YES _ _ _ _ _ _ _ NEC H4) in H3; inv H3.
  rewrite (necR_PURE _ _ _ _ _ NEC H4) in H3; inv H3.
exists (mkJuicyMem m phi H H0 H1 H2).
apply age1_juicy_mem_unpack''; simpl; auto.
Qed.

Lemma level1_juicy_mem: forall j: juicy_mem,
  age1_juicy_mem j = None <-> level (m_phi j) = 0%nat.
Proof.
intro x.
split; intro H.
apply age1_level0.
apply age1_juicy_mem_None1; auto.
apply age1_level0 in H.
apply age1_juicy_mem_None2.
auto.
Qed.

Lemma level2_juicy_mem: forall j1 j2: juicy_mem,
   age1_juicy_mem j1 = Some j2 -> level (m_phi j1) = S (level (m_phi j2)).
Proof.
intros x y H.
destruct (age1_juicy_mem_unpack x y H).
 apply age_level in H0. auto.
Qed.

Lemma juicy_mem_ageable_facts: ageable_facts juicy_mem (fun j => level (m_phi j)) age1_juicy_mem.
Proof.
constructor.
(*apply age1_juicy_mem_wf.*)
apply unage_juicy_mem.
apply level1_juicy_mem.
apply level2_juicy_mem.
Qed.

Instance juicy_mem_ageable: ageable juicy_mem :=
  mkAgeable _ (fun j => level (m_phi j)) age1_juicy_mem juicy_mem_ageable_facts.

Lemma level_juice_level_phi: forall (j: juicy_mem), level j = level (m_phi j).
Proof. intuition. Qed.

Lemma juicy_mem_ext: forall j1 j2, 
       m_dry j1 = m_dry j2  -> 
       m_phi j1 = m_phi j2 -> 
       j1=j2.
Proof.
intros.
destruct j1; destruct j2; simpl in *.
subst.
f_equal; apply proof_irr.
Qed.

Lemma perm_of_sh_pshare: forall rsh (sh: pshare), 
   exists p,  perm_of_sh rsh (pshare_sh sh) = Some p.
Proof.
intros sh.
unfold perm_of_sh.
if_tac. subst.
if_tac.
contradiction Share.nontrivial; auto.
intro sh. 
if_tac; eauto.
if_tac; eauto.
intros.
if_tac; eauto.
if_tac; eauto.
if_tac; eauto.
destruct sh0; simpl in *.
subst x.
clear - n.
elimtype False.
generalize bot_identity; rewrite identity_unit_equiv; intro.
apply (n _ H).
Qed.

Lemma perm_of_sh_fullshare: perm_of_sh Share.top fullshare = Some Freeable.
Proof. unfold perm_of_sh. rewrite if_true by auto. rewrite if_true by auto. auto. Qed.

Lemma unage_writable: forall (phi phi': rmap) loc,
  age phi phi' -> writable loc phi' -> writable loc phi.
Proof.
intros.
simpl in *.
apply age1_resource_at with (loc := loc) (r := phi @ loc) in H.
destruct (phi' @ loc); try contradiction.
unfold writable.
destruct (phi @ loc); try discriminate.
inv H. auto.
destruct (phi' @ loc); inv H0.
rewrite resource_at_approx. auto.
Qed.

Lemma unage_readable: forall (phi phi': rmap) loc,
  age phi phi' -> readable loc phi' -> readable loc phi.
Proof.
intros.
simpl in *.
apply age1_resource_at with (loc := loc) (r := phi @ loc) in H.
 2: symmetry; apply resource_at_approx.
destruct (phi' @ loc); try inv H0.
destruct (phi @ loc); try inv H.
auto.
Qed.

Lemma readable_inv: forall phi loc, readable loc phi ->
  exists rsh, exists sh, exists v, exists pp, phi @ loc = YES rsh sh (VAL v) pp.
Proof.
simpl.
intros phi loc H.
destruct (phi @ loc); try solve [inversion H].
destruct k; try inv H.
eauto.
Qed.

(* resource coherence *)

(* FIXME: put somewhere else. *)
Definition fmap_option {A B} (v: option A) (m: B) (f: A -> B): B :=
  match v with
    | None => m
    | Some v' => f v'
  end.

Lemma resource_at_make_rmap: forall f V lev H, resource_at (proj1_sig (make_rmap f V lev H)) = f.
refine (fun f V lev H => match proj2_sig (make_rmap f V lev H) with
                           | conj _ RESOURCE_AT => RESOURCE_AT
                         end).
Qed.

Lemma resource_at_remake_rmap: forall f V lev H, resource_at (proj1_sig (remake_rmap f V lev H)) = f.
refine (fun f V lev H => match proj2_sig (remake_rmap f V lev H) with
                           | conj _ RESOURCE_AT => RESOURCE_AT
                         end).
Qed.

Lemma level_make_rmap: forall f V lev H, @level rmap _ (proj1_sig (make_rmap f V lev H)) = lev.
refine (fun f V lev H => match proj2_sig (make_rmap f V lev H) with
                           | conj LEVEL _ => LEVEL
                         end).
Qed.

Lemma level_remake_rmap: forall f V lev H, @level rmap _ (proj1_sig (remake_rmap f V lev H)) = lev.
refine (fun f V lev H => match proj2_sig (remake_rmap f V lev H) with
                           | conj LEVEL _ => LEVEL
                         end).
Qed.

(* Here we build the [rmap]s that correspond to [store]s, [alloc]s and [free]s on the dry memory. *)
Section inflate.
Variables (m: mem) (phi: rmap).

Lemma phi_valid: valid (resource_at phi).
Proof. unfold valid; apply rmap_valid. Qed.

Definition inflate_initial_mem' (w: rmap) (loc: address) :=
   match access_at m loc Cur with
           | Some Freeable => YES Share.top pfullshare (VAL (contents_at m loc)) NoneP
           | Some Writable => YES extern_retainer pfullshare (VAL (contents_at m loc)) NoneP
           | Some Readable => YES extern_retainer read_sh (VAL (contents_at m loc)) NoneP
           | Some Nonempty => 
                         match w @ loc with PURE _ _ => w @ loc | _ => NO extern_retainer end
           | None =>  NO Share.bot 
         end.

Lemma inflate_initial_mem'_fmap:
 forall w, resource_fmap (approx (level w)) (approx (level w)) oo inflate_initial_mem' w = 
                inflate_initial_mem' w.
Proof.
unfold valid, CompCert_AV.valid, compose.
intros.
unfold inflate_initial_mem'.
extensionality loc.
destruct (access_at m loc); try destruct p; 
  try solve [unfold resource_fmap; f_equal; try apply preds_fmap_NoneP].
rewrite <- level_core.
  case_eq (w @ loc);intros; try reflexivity.
  rewrite <- H. rewrite level_core. apply resource_at_approx.
Qed.

Lemma inflate_initial_mem'_valid:
  forall lev, CompCert_AV.valid (res_option oo inflate_initial_mem' lev).
Proof.
unfold valid, CompCert_AV.valid, compose, inflate_initial_mem'.
intros lev b ofs.
destruct (access_at m (b, ofs)); try destruct p; simpl; auto.
 case_eq (lev @ (b,ofs)); intros; simpl; auto.
Qed.

Definition inflate_initial_mem (w: rmap): rmap :=
    proj1_sig (make_rmap (inflate_initial_mem' w) (inflate_initial_mem'_valid w) _ 
            (inflate_initial_mem'_fmap w)).

Lemma inflate_initial_mem_level: forall w, level (inflate_initial_mem w) = level w.
Proof.
intros; unfold inflate_initial_mem, inflate_initial_mem'. 
rewrite level_make_rmap; auto.
Qed.

Definition all_VALs (phi: rmap) := 
  forall l, match phi @ l with
              | YES _ _ k _ => isVAL k
              | _ => True
            end.

Lemma inflate_initial_mem_all_VALs: forall lev, all_VALs (inflate_initial_mem lev).
Proof.
unfold inflate_initial_mem, inflate_initial_mem', all_VALs.
intros; rewrite resource_at_make_rmap.
destruct (access_at m l); try destruct p; auto.
 case (lev @ l); simpl; intros; auto.
Qed.

(* FIXME
   Build an rmap that's identical to phi except where m has allocated. *)
Definition inflate_alloc: rmap.
 refine (proj1_sig (remake_rmap (fun loc =>
   fmap_option (res_option (phi @ loc))
       
  (* phi = NO *)
  (fmap_option (access_at m loc Cur)
    (NO Share.bot)
    (fun p => 
      match p with
        | Freeable => YES Share.top pfullshare (VAL (contents_at m loc)) NoneP
        | _ => NO Share.top
      end))
       
  (* phi = YES *)
  (fun _ => phi @ loc)) _ (level phi) _)).
Proof.
assert (VALID: valid (resource_at phi)) by (apply phi_valid).
unfold valid, CompCert_AV.valid in *.
unfold compose in *.
intros b ofs.
specialize VALID with b ofs.
unfold fmap_option.
destruct (phi @ (b, ofs)); simpl in *; auto.
destruct (access_at m (b, ofs)); simpl in *; auto.
destruct p; simpl in *; auto.
destruct k; simpl in *; auto.
intros i H.
specialize (VALID i H).
destruct (phi @ (b, ofs + i)); simpl in *; auto; try discriminate.
destruct VALID as [n [H H0]].
exists n.
split; auto.
destruct (phi @ (b, ofs - z)); simpl in *; auto; try discriminate.

(* NO *)
destruct (access_at m (b, ofs)); simpl; auto. destruct p0; simpl; auto.

(* YES *)
intro.
case_eq (phi @ l); simpl; intros; auto.
case_eq (access_at m l Cur); simpl; intros; auto.
right; destruct p; simpl; auto.
left; exists phi; split; auto.
right; destruct  (access_at m l Cur); simpl; auto.
destruct p0; simpl; auto.
Defined.

Lemma approx_map_idem: forall n (lp: preds), 
  preds_fmap (approx n) (approx n) (preds_fmap (approx n) (approx n) lp) =
  preds_fmap (approx n) (approx n) lp.
Proof.
intros n ls; unfold preds_fmap.
destruct ls.
rewrite <- compose_assoc.
rewrite (approx_oo_approx n).
auto.
Qed.

(* Build an [rmap] that's identical to [phi] except where [m] has stored. *)
Definition inflate_store: rmap. refine (
proj1_sig (make_rmap (fun loc =>
  match phi @ loc with
    | YES rsh sh (VAL _) _ => YES rsh sh (VAL (contents_at m loc)) NoneP
    | YES _ _ _ _ => resource_fmap (approx (level phi)) (approx (level phi)) (phi @ loc)
    | _ => phi @ loc
  end) _ (level phi) _)).
Proof.
assert (VALID: valid (resource_at phi)) by (apply phi_valid).       
unfold valid, CompCert_AV.valid in *.
unfold compose in *.
intros b ofs.
specialize VALID with b ofs.
remember (phi @ (b, ofs)) as HPHI.
destruct HPHI; simpl; auto.
destruct k; simpl in *; auto.
intros i H1.
specialize VALID with i.
destruct (phi @ (b, ofs + i)); auto.
destruct k; simpl; auto.
simpl in VALID.
assert (H2: Some (p1, VAL m0) = Some (p, CT i)).
apply (VALID H1).
inversion H2.
destruct VALID as [n [H1 H0]].
exists n.
split; auto.
destruct (phi @ (b, ofs - z)); simpl in *; auto.
inversion H0; subst; auto.

unfold compose.
extensionality l.
destruct l as (b, ofs).
remember (phi @ (b, ofs)) as HPHI.
destruct HPHI; auto.
(* YES *)
destruct k; try solve
  [ unfold resource_fmap; rewrite preds_fmap_NoneP; auto
  | unfold resource_fmap; rewrite approx_map_idem; auto ].
rewrite HeqHPHI.
apply resource_at_approx.
Defined.

End inflate.

Lemma adr_inv0: forall (b b': block) (ofs ofs': Z) (sz: Z),
  ~ adr_range (b, ofs) sz (b', ofs') ->
  b <> b' \/ ~ ofs <= ofs' < ofs + sz.
Proof.
intros until sz.
intro H.
destruct (peq b b').
right; intro Contra.
apply H.
unfold adr_range.
auto.
left; intro Contra.
apply n; auto.
Qed.

Lemma adr_inv: forall (b b': block) (ofs ofs': Z) ch, 
  ~ adr_range (b, ofs) (size_chunk ch) (b', ofs') ->
  b <> b' \/ ~ ofs <= ofs' < ofs + size_chunk ch.
Proof. intros until ch; intros H1; eapply adr_inv0; eauto. Qed.

Lemma range_inv0: forall ofs ofs' sz, 
  ~ ofs <= ofs' < ofs + sz ->
  ofs' < ofs \/ ofs' >= ofs + sz.
Proof.
intros until sz; intro H.
destruct (zle ofs ofs'); destruct (zlt ofs' (ofs + sz)); omega.
Qed.

Lemma range_inv: forall ofs ofs' ch, 
  ~ ofs <= ofs' < ofs + size_chunk ch ->
  ofs' < ofs \/ ofs' >= ofs + size_chunk ch.
Proof. intros; eapply range_inv0; eauto. Qed.

Lemma perm_of_sh_Freeable_top: forall rsh sh, perm_of_sh rsh sh = Some Freeable -> 
     (rsh, sh) = (Share.top, Share.top).
Proof.
intros rsh sh H.
unfold perm_of_sh in H.
repeat if_tac in H; solve [inversion H | auto].
Qed.

Lemma nextblock_access_empty: forall m b ofs k, (b >= nextblock m)%positive
  -> access_at m (b, ofs) k = None.
Proof.
intros.
unfold access_at. simpl.
apply (nextblock_noaccess m b ofs k).
auto.
Qed.

Section initial_mem.
Variables (m: mem) (w: rmap).

Definition initial_rmap_ok := 
   forall loc, ((fst loc >= nextblock m)%positive -> core w @ loc = NO Share.bot) /\
                   (match w @ loc with 
                    | PURE _ _ => (fst loc < nextblock m)%positive /\ 
                                           access_at m loc Cur = Some Nonempty /\  
                                            max_access_at m loc = Some Nonempty 
                    | _ => True end).
Hypothesis IOK: initial_rmap_ok.
End initial_mem.

Definition empty_retainer (loc: address) := Share.bot.

Lemma perm_of_freeable: perm_of_sh Share.top fullshare = Some Freeable.
Proof.
unfold perm_of_sh.
rewrite if_true by auto. rewrite if_true by auto. auto.
Qed.

Lemma perm_of_writable: 
   forall sh, sh<>Share.top -> perm_of_sh sh fullshare = Some Writable.
Proof.
intros. unfold perm_of_sh. rewrite if_true by auto. rewrite if_false by auto. auto.
Qed.

Lemma perm_of_readable:
  forall sh sh', sh <> Share.bot -> sh <> Share.top -> perm_of_sh sh' sh = Some Readable.
Proof.
intros. unfold perm_of_sh. rewrite if_false by auto. rewrite if_false by auto. auto.
Qed.

Lemma perm_of_nonempty:
  forall sh, sh <> Share.bot -> perm_of_sh sh Share.bot = Some Nonempty.
Proof.
intros. unfold perm_of_sh. rewrite if_false. rewrite if_true by auto.
rewrite if_false by auto; auto.
intro; contradiction Share.nontrivial; auto.
Qed.

Lemma perm_of_empty:
    perm_of_sh Share.bot Share.bot = None.
Proof.
intros. unfold perm_of_sh. rewrite if_false. rewrite if_true by auto.
rewrite if_true by auto. auto.
intro; contradiction Share.nontrivial; auto.
Qed.

Definition initial_mem (m: mem) lev (IOK: initial_rmap_ok m lev) : juicy_mem.
 refine (mkJuicyMem m  (inflate_initial_mem m lev) _ _ _ _); 
  unfold inflate_initial_mem, inflate_initial_mem';
  hnf; intros;  try rewrite resource_at_make_rmap in *.
* (* contents_cohere *)
revert H; case_eq (access_at m loc Cur); intros.
 destruct p; inv H0; auto.
 revert H2; case_eq (lev @ loc); intros; congruence.
 destruct (max_access_at m loc); try destruct p; try congruence.
* (* access_cohere *)
 symmetry.
 destruct (access_at m loc) _eqn:?; try destruct p; auto; simpl.
 apply perm_of_freeable.
 apply perm_of_writable.
 apply extern_retainer_neq_top.
 apply perm_of_readable.
 apply extern_retainer_neq_bot.
 apply extern_retainer_neq_top.
 destruct (IOK loc).
 destruct (lev @ loc).
 simpl; rewrite if_false by apply extern_retainer_neq_bot; auto.
 simpl; rewrite if_false by apply extern_retainer_neq_bot; auto.
 reflexivity.
 rewrite !if_true; auto.
* (* max_access_cohere *)
generalize (perm_cur_max m (fst loc) (snd loc)); unfold perm; intros.
case_eq (access_at m loc Cur); try destruct p; intros.
unfold perm_order'', perm_order', max_access_at in *.
simpl; rewrite perm_of_freeable.
apply H.
unfold access_at in H0. rewrite H0. constructor.
simpl. rewrite perm_of_writable.
unfold perm_order'', perm_order', max_access_at, access_at in *.
rewrite H0 in *.
specialize (H Writable). spec H. constructor.
apply H.
apply extern_retainer_neq_top.
rewrite perm_of_readable.
unfold perm_order'', perm_order', max_access_at, access_at in *.
rewrite H0 in *.
apply H. constructor.
clear; unfold read_sh.
unfold split_pshare; simpl.
apply fst_split_fullshare_not_bot.
apply fst_split_fullshare_not_top.
destruct (IOK loc).
destruct (lev @ loc).
 rewrite perm_of_nonempty by apply extern_retainer_neq_bot.
 unfold max_access_at, access_at in *.
 rewrite H0 in H.
 specialize (H Nonempty). spec H. constructor.
 apply H.
 rewrite perm_of_nonempty by apply extern_retainer_neq_bot.
 unfold max_access_at, access_at in *.
 rewrite H0 in H.
 specialize (H Nonempty). spec H. constructor.
 apply H.
destruct H2; auto.
rewrite perm_of_empty. destruct (max_access_at m loc); try constructor.
* (* alloc_cohere *)
unfold access_at.
unfold block; rewrite (nextblock_noaccess m (fst loc) (snd loc) Cur); auto.
Defined.

Definition juicy_mem_level (j: juicy_mem) (lev: nat) :=
  level (m_phi j) = lev.

Lemma initial_mem_level: forall lev m j IOK,
  j = initial_mem m lev IOK -> juicy_mem_level j (level lev).
Proof.
intros.
destruct j; simpl.
unfold initial_mem in H.
inversion H; subst.
unfold juicy_mem_level. simpl.
erewrite inflate_initial_mem_level; eauto.
Qed.

Lemma initial_mem_all_VALs: forall lev m j IOK, j = initial_mem m lev IOK
  -> all_VALs (m_phi j). 
Proof.
intros until 1; intros (b, ofs).
destruct j; unfold initial_mem in H; inversion H; subst.
simpl.
unfold inflate_initial_mem, inflate_initial_mem'; rewrite resource_at_make_rmap.
destruct (access_at m (b, ofs)); try destruct p; auto.
case_eq (lev @ (b,ofs)); intros; auto.
Qed.

Lemma perm_mem_access: forall m b ofs p, 
  perm m b ofs Cur p ->
  exists p', (perm_order p' p /\ access_at m (b, ofs) Cur = Some p').
Proof.
intros.
rewrite perm_access in H. red in H.
destruct (access_at m (b, ofs) Cur); try contradiction; eauto.
Qed.

Section store.
Variables (jm: juicy_mem) (m': mem)
          (ch: memory_chunk) (b: block) (ofs: Z) (v: val)
          (STORE: store ch (m_dry jm) b ofs v = Some m').

Lemma store_phi_elsewhere_eq: forall rsh sh mv loc', 
  ~ adr_range (b, ofs) (size_chunk ch) loc' 
  -> (m_phi jm) @ loc' = YES rsh sh (VAL mv) NoneP -> contents_at m' loc' = mv.
Proof.
destruct jm. simpl in *. clear jm. 
intros.
unfold contents_at.
rewrite store_mem_contents with 
  (chunk := ch) (m1 := m) (b := b) (ofs := ofs) (v := v); auto.
destruct loc' as [b' ofs']. simpl.
destruct (peq b' b).
(* b' = b *)
destruct (adr_inv b b' ofs ofs' ch H).
symmetry in e.
contradiction.
(* b' = b /\ ~ ofs <= ofs' < ofs + size_chunk ch *)
subst.
rewrite PMap.gss.
rewrite setN_outside.
destruct (JMcontents _ _ _ _ _ H0) as [H5 _].
apply H5.
destruct (range_inv _ _ _ H1) as [H1'|H1'].
left; auto.
right.
rewrite encode_val_length.
rewrite <- size_chunk_conv.
auto.

(* b' <> b *)
rewrite PMap.gso; auto.
destruct (JMcontents _ _ _ _ _ H0) as [H1 _].
apply H1.
Qed.

Definition store_juicy_mem: juicy_mem.
 refine (mkJuicyMem m' (inflate_store m' (m_phi jm)) _ _ _ _).
(* contents_cohere *)
intros rsh sh' v' loc' pp H2.
unfold inflate_store in H2; rewrite resource_at_make_rmap in H2.
destruct (m_phi jm @ loc'); try destruct k; try solve [inversion H2].
inversion H2; auto.
(* access_cohere *)
intro loc; generalize (juicy_mem_access jm loc); intro H0.
unfold inflate_store; rewrite resource_at_make_rmap.
rewrite <- (Memory.store_access _ _ _ _ _ _ STORE).
destruct (m_phi jm @ loc); try destruct k; auto.
(* max_access_cohere *)
intro loc; generalize (juicy_mem_max_access jm loc); intro H1.
unfold inflate_store; rewrite resource_at_make_rmap.
unfold max_access_at in *.
rewrite <- (Memory.store_access _ _ _ _ _ _ STORE).
apply nextblock_store in STORE. 
destruct (m_phi jm @ loc); auto.
destruct k; simpl; try congruence.  rewrite STORE; auto.
(* alloc_cohere *)
hnf; intros.
unfold inflate_store. rewrite resource_at_make_rmap.
generalize (juicy_mem_alloc_cohere jm loc); intro.
rewrite (nextblock_store _ _ _ _ _ _ STORE) in H.
rewrite (H0 H). auto.
Defined.

End store.

Section storebytes.
Variables (jm: juicy_mem) (m': mem) (b: block) (ofs: Z) (bytes: list memval)
  (STOREBYTES: storebytes (m_dry jm) b ofs bytes = Some m').

Lemma storebytes_phi_elsewhere_eq: forall rsh sh mv loc', 
  ~ adr_range (b, ofs) (Zlength bytes) loc' -> 
  (m_phi jm) @ loc' = YES rsh sh (VAL mv) NoneP -> 
  contents_at m' loc' = mv.
Proof.
destruct jm. simpl in *. clear jm. 
intros.
unfold contents_at.
rewrite storebytes_mem_contents with 
  (m1 := m) (b := b) (ofs := ofs) (bytes := bytes); auto.
destruct loc' as [b' ofs']. simpl.
destruct (peq b' b).
(* b' = b *)
destruct (adr_inv0 b b' ofs ofs' (Zlength bytes) H).
symmetry in e.
contradiction.
(* b' = b /\ ~ ofs <= ofs' < ofs + size_chunk ch *)
subst.
rewrite PMap.gss.
rewrite setN_outside.
destruct (JMcontents _ _ _ _ _ H0) as [H5 _].
apply H5.
destruct (range_inv0 _ _ _ H1) as [H1'|H1'].
left; auto.
right.
rewrite <-Zlength_correct; auto.
(* b' <> b *)
rewrite PMap.gso; auto.
destruct (JMcontents _ _ _ _ _ H0) as [H1 _].
apply H1.
Qed.

Definition storebytes_juicy_mem: juicy_mem.
 refine (mkJuicyMem m' (inflate_store m' (m_phi jm)) _ _ _ _).
(* contents_cohere *)
intros rsh sh' v' loc' pp H2.
unfold inflate_store in H2; rewrite resource_at_make_rmap in H2.
destruct (m_phi jm @ loc'); try destruct k; try solve [inversion H2].
inversion H2; auto.
(* access_cohere *)
intro loc; generalize (juicy_mem_access jm loc); intro H0.
unfold inflate_store; rewrite resource_at_make_rmap.
rewrite <- (Memory.storebytes_access _ _ _ _ _ STOREBYTES).
destruct (m_phi jm @ loc); try destruct k; auto.
(* max_access_cohere *)
intro loc; generalize (juicy_mem_max_access jm loc); intro H1.
unfold inflate_store; rewrite resource_at_make_rmap.
unfold max_access_at in *.
rewrite <- (Memory.storebytes_access _ _ _ _ _ STOREBYTES).
assert (H88:=nextblock_storebytes _ _ _ _ _ STOREBYTES).
destruct (m_phi jm @ loc); try rewrite H88; auto.
destruct k; simpl; try rewrite H88; auto.
(* alloc_cohere *)
hnf; intros.
unfold inflate_store. rewrite resource_at_make_rmap.
generalize (juicy_mem_alloc_cohere jm loc); intro.
rewrite (nextblock_storebytes _ _ _ _ _ STOREBYTES) in H.
rewrite (H0 H). 
auto.
Defined.

End storebytes.

Lemma free_smaller_None : forall m b b' ofs lo hi m',
  access_at m (b, ofs) Cur = None
  -> free m b' lo hi = Some m'
  -> access_at m' (b, ofs) Cur = None.
Proof.
intros.
destruct (adr_range_dec (b',lo) (hi-lo) (b,ofs)).
destruct a; simpl in *.
subst b'; apply free_access with (ofs:=ofs) in H0; [ | omega].
destruct H0.
pose proof (Memory.access_cur_max m' (b,ofs)).
rewrite H1 in H3; simpl in H3.
destruct (access_at m' (b, ofs) Cur); auto; contradiction.
rewrite <- H. symmetry.
eapply free_access_other; eauto.
destruct (eq_block b b'); auto; right.
simpl in n.
assert (~(lo <= ofs < lo + (hi - lo))) by intuition.
omega.
Qed.

Lemma free_nadr_range_eq : forall m b b' ofs' lo hi m',
  ~ adr_range (b, lo) (hi - lo) (b', ofs')
  -> free m b lo hi = Some m'
  -> access_at m (b', ofs') = access_at m' (b', ofs')
  /\  contents_at m (b', ofs') = contents_at m' (b', ofs').
Proof.
intros.
split.
extensionality k.
apply (free_access_other _ _ _ _ _ H0 b' ofs' k).
destruct (eq_block b b'); auto; right.
simpl in H.
assert (~(lo <= ofs' < lo + (hi - lo))) by intuition.
omega.
unfold contents_at.
simpl.
Transparent free.
unfold free in H0.
Opaque free.
if_tac in H0; inv H0.
unfold unchecked_free.
simpl.
reflexivity.
Qed.

Section free.
Variables (jm :juicy_mem) (m': mem)
          (b: block) (lo hi: Z)
          (FREE: free (m_dry jm) b lo hi = Some m')
          (PERM: forall ofs, lo <= ofs < hi ->
                      perm_of_res (m_phi jm @ (b,ofs)) = Some Freeable).

Definition inflate_free: rmap. refine (
proj1_sig (make_rmap (fun loc =>
  if adr_range_dec (b,lo) (hi-lo) loc then NO Share.bot else m_phi jm @ loc)
     _ (level (m_phi jm)) _)).
Proof.
* (* AV.valid *)
assert (VALID: valid (resource_at (m_phi jm))) by (apply phi_valid).
intros b' ofs'.
specialize (VALID b' ofs').
unfold compose in *; simpl in *.
if_tac; [simpl; now auto | ].
destruct (m_phi jm @ (b', ofs')) eqn:?; try destruct k; simpl in *; auto.
 +
 intros. specialize (VALID _ H0).
 if_tac; [ | now auto].
 destruct H1; subst b'.
 specialize (PERM (ofs'+i)).  spec PERM; [omega | ].
 destruct (m_phi jm @ (b, ofs' + i)); inv  VALID. inv PERM.
 +
 destruct VALID as [n [? ?]]; exists n; split; auto.
 if_tac; auto.
 destruct H2; subst b'.
 specialize (PERM (ofs'-z)).  spec PERM; [omega | ].
 destruct (m_phi jm @ (b, ofs' -z)); inv  H1. inv PERM.
*
unfold compose.
extensionality l.
destruct l as (b', ofs').
if_tac; try reflexivity.
apply resource_at_approx.
Defined.


Definition free_juicy_mem: juicy_mem.
 generalize (juicy_mem_contents jm); intro.
 generalize (juicy_mem_access jm); intro.
 generalize (juicy_mem_max_access jm); intro.
 refine (mkJuicyMem m' inflate_free _ _ _ _).
* (* contents_cohere *)
unfold contents_cohere in *.
intros rsh' sh' v' [b' ofs'] pp H2.
unfold access_cohere in H0.
specialize (H0 (b', ofs')).
unfold inflate_free in H2; rewrite resource_at_make_rmap in H2.
if_tac in H2; [inv H2 | ]. rename H3 into H8.
remember (m_phi jm @ (b', ofs')) as HPHI.
destruct HPHI; try destruct k; inv H2. 
assert (H3: contents_at (m_dry jm) (b', ofs') = v') by (eapply H; eauto).
assert (H4: m' = unchecked_free (m_dry jm) b lo hi) by (apply free_result; auto).
rewrite H4.
unfold unchecked_free, contents_at; simpl.
split; auto.
symmetry in HeqHPHI.
destruct (H _ _ _ _ _ HeqHPHI); auto.
* (* access_cohere *)
intros [b' ofs']; spec H0 (b', ofs').
unfold inflate_free; rewrite resource_at_make_rmap.
destruct (adr_range_dec (b,lo) (hi-lo) (b',ofs')).
 + (* adr_range *)
destruct a as [H2 H3].
replace (lo+(hi-lo)) with hi in H3 by omega.
subst b'.
replace (access_at m' (b, ofs') Cur) with (@None permission).
simpl. rewrite if_true by auto. auto.
destruct (free_access _ _ _ _ _ FREE ofs' H3).
pose proof (Memory.access_cur_max m' (b,ofs')). rewrite H4 in H5.
simpl  in H5.
destruct (access_at m' (b, ofs') Cur); auto; contradiction.
+ (* ~adr_range *)
destruct (free_nadr_range_eq _ _ _ _ _ _ _ n FREE) as [H2 H3].
rewrite H2 in *. clear H2 H3.
case_eq (m_phi jm @ (b', ofs')); intros; rewrite H2 in *; auto.
* (* max_access_cohere *)
intros [b' ofs']. specialize (H1 (b',ofs')).
unfold inflate_free. unfold max_access_at. rewrite resource_at_make_rmap.
destruct (adr_range_dec (b,lo) (hi-lo) (b',ofs')).
 + (* adr_range *)
destruct a as [H2 H3].
replace (lo+(hi-lo)) with hi in H3 by omega.
subst b'.
replace (access_at m' (b, ofs') Max) with (@None permission).
simpl. rewrite perm_of_empty. auto.
destruct (free_access _ _ _ _ _ FREE ofs' H3). auto.
+ (* ~ (adr_range_dec (b,lo) (hi-lo) loc) *)
clear PERM.
unfold max_access_at.
destruct (free_nadr_range_eq _ _ _ _ _ _ _ n FREE) as [H2 H3].
rewrite <- H2.
rewrite (nextblock_free _ _ _ _ _ FREE).
auto.
* (* alloc_cohere *)
hnf; intros.
unfold inflate_free. rewrite resource_at_make_rmap.
pose proof (juicy_mem_alloc_cohere jm loc).
rewrite (nextblock_free _ _ _ _ _ FREE) in H2; auto.
rewrite H3; auto.
if_tac; auto.
Defined.

End free.

Lemma free_not_freeable_eq : forall m b lo hi m' b' ofs',
  free m b lo hi = Some m'
  -> access_at m (b', ofs') Cur <> Some Freeable
  -> access_at m (b', ofs') Cur = access_at m' (b', ofs') Cur.
Proof.
intros.
destruct (adr_range_dec (b,lo) (hi-lo) (b',ofs')).
destruct a.
subst b'.
destruct (free_access _ _ _ _ _ H ofs'); [omega |].
contradiction.
apply (free_access_other _ _ _ _ _ H).
destruct (eq_block b' b); auto; right.
subst b'.
simpl in n. assert (~( lo <= ofs' < lo + (hi - lo))) by intuition; omega.
Qed.

(* The empty juicy memory *)

Definition after_alloc' 
  (lo hi: Z) (b: block) (phi: rmap)(H: forall ofs, phi @ (b,ofs) = NO Share.bot)
  : address -> resource := fun loc =>
    if adr_range_dec (b,lo) (hi-lo) loc 
      then YES Share.top pfullshare (VAL Undef) NoneP
      else phi @ loc.

Lemma adr_range_eq_block : forall b ofs n b' ofs',
  adr_range (b,ofs) n (b',ofs') ->
  b=b'.
Proof.
unfold adr_range; intros.
destruct H; auto.
Qed.

Lemma after_alloc'_valid : forall lo hi b phi H,
  valid (after_alloc' lo hi b phi H).
Proof.
intros; hnf; intros.
unfold compose, after_alloc'.
if_tac; simpl; auto.
case_eq (phi @ (b0, ofs)); intros; simpl; auto.
generalize (rmap_valid phi). intro H4.
unfold AV.valid, compose in H4.
spec H4 b0 ofs.
rewrite H1 in H4; simpl in H4.
destruct k; auto.
intros.
if_tac.
assert (b = b0) by (eapply adr_range_eq_block; eauto).
subst. congruence.
auto.
destruct H4 as [? [? ?]]; eexists; split; eauto.
if_tac; eauto.
assert (b = b0) by (eapply adr_range_eq_block; eauto).
subst. congruence.
Qed.

Lemma after_alloc'_ok : forall lo hi b phi H,
  resource_fmap (approx (level phi)) (approx (level phi)) oo (after_alloc' lo hi b phi H)
  = after_alloc' lo hi b phi H.
Proof.
intros.
unfold resource_fmap, compose, after_alloc'.
extensionality loc.
if_tac.
rewrite preds_fmap_NoneP; auto.
case_eq (phi @ loc); intros; auto.
generalize H1; intros. 
apply necR_YES with (phi':=phi) in H1; eauto.
rewrite <- H1.
auto.
generalize (resource_at_approx phi loc); rewrite H1; auto.
Qed.

Definition after_alloc
  (lo hi: Z) (b: block) (phi: rmap)(H: forall ofs, phi @ (b,ofs) = NO Share.bot) : rmap :=
  proj1_sig (make_rmap (after_alloc' lo hi b phi H)
    (after_alloc'_valid lo hi b phi H) 
    (level phi)
    (after_alloc'_ok lo hi b phi H)).

Definition mod_after_alloc' (phi: rmap) (lo hi: Z) (b: block) 
  : address -> resource := fun loc =>
    if adr_range_dec (b,lo) (hi-lo) loc 
      then YES Share.top pfullshare (VAL Undef) NoneP
      else core phi @ loc.

Lemma mod_after_alloc'_valid : forall phi lo hi b,
  valid (mod_after_alloc' phi lo hi b).
Proof.
intros; hnf; intros.
unfold compose, mod_after_alloc'.
if_tac; simpl; auto.
rewrite <- core_resource_at.
destruct (phi @ (b0,ofs)).
rewrite core_NO; simpl; auto.
rewrite core_YES; simpl; auto.
rewrite core_PURE; simpl; auto.
Qed.

Lemma mod_after_alloc'_ok : forall phi lo hi b,
  resource_fmap (approx (level phi)) (approx (level phi)) oo (mod_after_alloc'  phi lo hi b)
  = mod_after_alloc' phi lo hi b.
Proof.
intros.
unfold resource_fmap, compose, mod_after_alloc'.
extensionality loc.
if_tac; auto.
rewrite preds_fmap_NoneP; auto.
case_eq (core phi @ loc); intros; auto; f_equal;
rewrite <- level_core;
generalize (resource_at_approx (core phi) loc); rewrite H0; intro; injection H1; auto.
Qed.

Definition mod_after_alloc (phi: rmap) (lo hi: Z) (b: block) :=
  proj1_sig (make_rmap (mod_after_alloc' phi lo hi b)
    (mod_after_alloc'_valid phi lo hi b) 
    _
    (mod_after_alloc'_ok phi lo hi b)).

Transparent alloc.

Lemma adr_range_inv: forall loc loc' n,
  ~ adr_range loc n loc' ->
  fst loc <> fst loc' \/ (fst loc=fst loc' /\ ~snd loc <= snd loc' < snd loc + n).
Proof.
intros until n.
intro H.
destruct (peq (fst loc) (fst loc')).
right; split; auto; intro Contra.
apply H.
unfold adr_range.
destruct loc,loc'.
auto.
left; intro Contra.
apply n0; auto.
Qed.

Lemma dry_noperm_juicy_nonreadable : forall m loc, 
  access_at (m_dry m) loc Cur = None ->   ~readable loc (m_phi m).
Proof.
intros.
rewrite (juicy_mem_access m loc) in H.
intro. hnf in H0.
destruct (m_phi m @loc); simpl in *; auto.
destruct k as [x | | |]; try inv H.
unfold perm_of_sh in H2.
if_tac in H2. if_tac in H2; inv H2.
if_tac in H2.
destruct p. simpl in H1. subst x0.
clear - n; apply nonunit_nonidentity in n.
contradiction n; auto. 
inv H2.
Qed.

Lemma fullempty_after_alloc : forall m1 m2 lo n b ofs,
  alloc m1 lo n = (m2, b) ->
  access_at m2 (b, ofs) Cur = None \/ access_at m2 (b, ofs) Cur = Some Freeable.
Proof.
intros.
pose proof (alloc_access_same _ _ _ _ _ H ofs Cur).
destruct (range_dec lo ofs n). auto.
left.
rewrite <- (alloc_access_other _ _ _ _ _ H b ofs Cur) by (right; omega).
apply alloc_result in H.
subst.
apply nextblock_access_empty.
apply Pos.le_ge, Ple_refl.
Qed.

Lemma alloc_dry_unchanged_on : forall m1 m2 loc lo hi b0,
  alloc m1 lo hi = (m2, b0) ->
  ~adr_range (b0,lo) (hi-lo) loc ->
  access_at m1 loc = access_at m2 loc /\ 
  (access_at m1 loc Cur <> None -> contents_at m1 loc= contents_at m2 loc).
Proof.
intros.
destruct loc as [b z]; simpl.
split.
extensionality k.
eapply Memory.alloc_access_other; eauto.
simpl in H0.
destruct (eq_block b b0); auto. subst. right.
assert (~(lo <= z < lo + (hi - lo))) by intuition; omega.
intros.
unfold alloc in H.
inv H. unfold contents_at; simpl.
unfold adr_range in H0.
destruct (eq_dec b (nextblock m1)).
subst.
rewrite invalid_noaccess in H1; [ congruence |].
contradict H0.
red in H0. apply Plt_irrefl in H0. contradiction.
rewrite PMap.gso by auto.
auto.
Qed.

Lemma adr_range_zle_fact : forall b lo hi loc,
  adr_range (b,lo) (hi-lo) loc ->
  zle lo (snd loc) && zlt (snd loc) hi = true.
Proof.
unfold adr_range.
intros.
destruct loc; simpl in *.
destruct H.
destruct H0.
apply andb_true_iff.
split.
apply zle_true; auto.
apply zlt_true; omega.
Qed.

Lemma alloc_dry_updated_on : forall m1 m2 lo hi b loc,
  alloc m1 lo hi = (m2, b) ->
  adr_range (b, lo) (hi - lo) loc ->
  access_at m2 loc Cur=Some Freeable /\
  contents_at m2 loc=Undef.
Proof.
intros.
destruct loc as [b' z'].
split.
destruct H0. subst b'.
apply (alloc_access_same _ _ _ _ _ H). omega.
unfold contents_at; unfold alloc in H; inv H. simpl.
destruct H0; subst b'.
rewrite PMap.gss. rewrite ZMap.gi; auto.
Qed.

Definition resource_decay (nextb: block) (phi1 phi2: rmap) := 
  (level phi1 >= level phi2)%nat /\
 forall l: address,
  ((fst l >= nextb)%positive -> phi1 @ l = NO Share.bot) /\
  (resource_fmap (approx (level phi2)) (approx (level phi2)) (phi1 @ l) = (phi2 @ l) \/
  (exists rsh, exists v, exists v',
       resource_fmap (approx (level phi2)) (approx (level phi2)) (phi1 @ l) = YES rsh pfullshare (VAL v) NoneP /\ 
       phi2 @ l = YES rsh pfullshare (VAL v') NoneP)
  \/ ((fst l >= nextb)%positive /\ exists v, phi2 @ l = YES Share.top pfullshare (VAL v) NoneP)
  \/ (exists v, exists pp, phi1 @ l = YES Share.top pfullshare (VAL v) pp /\ phi2 @ l = NO Share.bot)).


Definition resource_nodecay (nextb: block) (phi1 phi2: rmap) := 
  (level phi1 >= level phi2)%nat /\
  forall l: address,
  ((fst l >= nextb)%positive -> phi1 @ l = NO Share.bot) /\
  (resource_fmap (approx (level phi2)) (approx (level phi2)) (phi1 @ l) = (phi2 @ l) \/
  (exists rsh, exists v, exists v',
       resource_fmap (approx (level phi2)) (approx (level phi2)) (phi1 @ l) = YES rsh pfullshare (VAL v) NoneP
      /\ phi2 @ l = YES rsh pfullshare (VAL v') NoneP)).

Lemma resource_nodecay_decay: 
   forall b phi1 phi2, resource_nodecay b phi1 phi2 -> resource_decay b phi1 phi2.
Proof. 
 unfold resource_decay, resource_nodecay; intros; destruct H; split; intros; try omega.
specialize (H0 l); intuition.
Qed.

Lemma resource_decay_refl: forall b phi, 
  (forall l, (fst l >= b)%positive -> phi @ l = NO Share.bot) ->
  resource_decay b phi phi.
Proof.
intros.
split; auto.
intros; split; auto.
left.
apply resource_at_approx.
Qed.

Lemma resource_decay_trans: forall b b' m1 m2 m3, 
  (b <= b')%positive ->
  resource_decay b m1 m2 -> resource_decay b' m2 m3 -> resource_decay b m1 m3.
Proof.
 intros until m3; intro Hbb; intros.
 destruct H as [H' H]; destruct H0 as [H0' H0]; split; [omega |].
 intro l; specialize (H l); specialize (H0 l).
 destruct H,H0.
 split.  auto.
 destruct H1.
 destruct H2. 
 left. rewrite <- H2.
 replace (resource_fmap (approx (level m3)) (approx (level m3)) (m1 @ l))
    with (resource_fmap (approx (level m3)) (approx (level m3))
              (resource_fmap (approx (level m2)) (approx (level m2)) (m1 @ l)))
  by (rewrite resource_fmap_fmap; rewrite approx_oo_approx' by auto; auto).
rewrite H1. auto.
 clear - Hbb H H1 H0 H2 H' H0'.
 right.
 destruct H2 as [[rsh2 [v2 [v2' [? ?]]]]|[[? [v ?]] |?]]; subst.
 left; exists rsh2,v2,v2'; split; auto.
 rewrite <- H1 in H2.
 rewrite resource_fmap_fmap in H2. rewrite approx_oo_approx' in H2 by omega.
 assumption.
 right; left. split. xomega. exists v; auto.
 right; right; auto.
 destruct H2 as [v [pp [? ?]]].
 rewrite H2 in H1. destruct (m1 @ l); inv H1. eauto.
 destruct H2.
 destruct H1 as [[rsh [v [v' [? ?]]]]|[[? [v ?]] |?]].
 right; left; exists rsh,v,v'; split. 
 rewrite <- (approx_oo_approx' (level m3) (level m2)) at 1 by auto.
 rewrite <- (approx'_oo_approx (level m3) (level m2)) at 2 by auto.
 rewrite <- resource_fmap_fmap. rewrite H1.
 unfold resource_fmap. rewrite preds_fmap_NoneP. auto.
 rewrite H3 in H2. rewrite <- H2.
 unfold resource_fmap. rewrite preds_fmap_NoneP. auto.
 right; right; left; split; auto. exists v. rewrite <- H2; rewrite <- H3.
 rewrite H3. 
 unfold resource_fmap. rewrite preds_fmap_NoneP. auto.
 right; right; right.
 destruct H1 as [v [pp [? ?]]].
 rewrite H3 in H2. simpl in H2. eauto.
 destruct H1 as [[rsh [v [v' [? ?]]]]|[[? [v ?]] |?]].
 destruct H2 as [[rsh2 [v2 [v2' [? ?]]]]|[[? [v2 ?]] |?]].
 right; left; exists rsh,v,v2'; split.
 rewrite <- (approx_oo_approx' (level m3) (level m2)) at 1 by auto.
 rewrite <- (approx'_oo_approx (level m3) (level m2)) at 2 by auto.
 rewrite <- resource_fmap_fmap. rewrite H1.
 unfold resource_fmap. rewrite preds_fmap_NoneP. auto.
 rewrite H3 in H2. rewrite H4. simpl in H2. inv H2; auto.
 right; right; left. split. xomega. exists v2; auto.
 right; right; right.
 destruct (m1 @ l); inv H1.
 destruct H2 as [vx [pp [? ?]]]. inversion2 H3 H1. eauto. 
 destruct H2 as [[rsh2 [v2 [v2' [? ?]]]]|[[? [v2 ?]] |?]].
 right; right; left; split; auto. exists v2'. rewrite H3 in H2; inv H2; auto.
 right; right; left; split; auto; exists v2; auto.
 left. destruct H2 as [v' [pp [? ?]]]. rewrite H4; rewrite H; auto.
 destruct H2 as [[rsh2 [v2 [v2' [? ?]]]]|[[? [v2 ?]] |?]].
 destruct H1 as [v' [pp [? ?]]].
 rewrite H4 in H2; inv H2.
 right; right; left; split. xomega. eauto.
 right; right; right.
 destruct H1 as [v1 [pp1 [? ?]]].
 destruct H2 as [v2 [pp2 [? ?]]].
 inversion2 H3 H2. 
Qed.

Lemma level_store_juicy_mem:
 forall jm m ch b i v H, level (store_juicy_mem jm m ch b i v H) = level jm.
Proof.
intros.
unfold store_juicy_mem. simpl.
unfold inflate_store; simpl. rewrite level_make_rmap. auto.
Qed.

Lemma level_storebytes_juicy_mem:
 forall jm m b i bytes H, level (storebytes_juicy_mem jm m b i bytes H) = level jm.
Proof.
intros.
unfold storebytes_juicy_mem. simpl.
unfold inflate_store; simpl. rewrite level_make_rmap. auto.
Qed.

Lemma inflate_store_resource_nodecay:
  forall (jm: juicy_mem) (m': mem)
          (ch: memory_chunk) (b: block) (ofs: Z) (v: val)
          (STORE: store ch (m_dry jm) b ofs v = Some m')
          (PERM: forall z, ofs <= z < ofs + size_chunk ch ->
                      perm_order'' (perm_of_res (m_phi jm @ (b,z))) (Some Writable))
          phi', 
  inflate_store m' (m_phi jm) = phi' -> resource_nodecay (nextblock (m_dry jm)) (m_phi jm) phi'.
Proof.
intros.
split.
subst; unfold inflate_store; simpl. rewrite level_make_rmap. auto.
intro l'.
split.
apply juicy_mem_alloc_cohere.
destruct (adr_range_dec (b, ofs) (size_chunk ch) l') as [HA | HA].
* (* adr_range *)
right.
unfold adr_range in HA.
destruct l' as (b', ofs').
destruct HA as [HA0 HA1].
subst b'.
assert (H0: range_perm (m_dry jm) b ofs (ofs + size_chunk ch) Cur Writable).
  cut (valid_access (m_dry jm) ch b ofs Writable).
  intros [? ?]; auto.
  eapply store_valid_access_3; eauto.
assert (H1: perm (m_dry jm) b ofs' Cur Writable) by (apply H0; auto).
generalize (juicy_mem_access jm (b, ofs')); intro ACCESS.
unfold perm, perm_order' in H1.
unfold access_at in ACCESS.
simpl in *.
destruct ((mem_access (m_dry jm)) !! b ofs' Cur) eqn:?H; try contradiction.
specialize (PERM ofs' HA1).
destruct ( m_phi jm @ (b, ofs') ) eqn:?H; try destruct k; simpl in PERM; try if_tac in PERM; try inv PERM.
destruct (juicy_mem_contents _ _ _ _ _ _ H3); subst.
assert (p0 = pfullshare). {
  clear - PERM.
  unfold perm_order'', perm_of_sh in PERM.
  if_tac in PERM.
  apply top_pfullshare; auto.
  if_tac in PERM. if_tac in PERM; try contradiction. inv PERM. inv PERM.
 }
 subst p0.
 do 3 econstructor; split; try reflexivity.
 unfold resource_fmap. rewrite preds_fmap_NoneP.
 reflexivity.
unfold inflate_store;  rewrite resource_at_make_rmap.
rewrite H3.
reflexivity.
* (* ~ adr_range *)
left.
assert (H0: level (m_phi jm) = level phi').
  rewrite <- H; unfold inflate_store; rewrite level_make_rmap; auto.
rewrite <- H.
unfold inflate_store; rewrite level_make_rmap; rewrite resource_at_make_rmap.
case_eq l'; intros b' ofs' e'; subst.
remember (m_phi jm @ (b', ofs')) as HPHI; destruct HPHI; try destruct k; auto;
  try solve [rewrite HeqHPHI; rewrite resource_at_approx; auto].
rewrite (store_phi_elsewhere_eq jm _ _ _ _ _ STORE t p m (b', ofs')); auto.
assert (H: p0 = NoneP).
  symmetry in HeqHPHI; 
  destruct  (juicy_mem_contents jm _ _ _ _ _ HeqHPHI); auto.
rewrite H. 
unfold resource_fmap; f_equal; try reflexivity. apply preds_fmap_NoneP.
assert (H: p0 = NoneP).
  symmetry in HeqHPHI;
  destruct  (juicy_mem_contents jm _ _ _ _ _ HeqHPHI); auto. 
rewrite H in HeqHPHI; clear H.
rewrite HeqHPHI; auto.
Qed.

Lemma inflate_free_resource_decay: 
 forall (jm :juicy_mem) (m': mem)
          (b: block) (lo hi: Z)
          (FREE: free (m_dry jm) b lo hi = Some m')
          (PERM: forall ofs : Z,
             lo <= ofs < hi -> perm_of_res (m_phi jm @ (b, ofs)) = Some Freeable),
   resource_decay (nextblock (m_dry jm)) (m_phi jm) (inflate_free jm b lo hi PERM).
Proof.
intros.
split.
unfold inflate_free; rewrite level_make_rmap; auto.
intros l.
split.
apply juicy_mem_alloc_cohere.
destruct (adr_range_dec (b, lo) (hi-lo) l) as [HA | HA].
* (* adr_range *)
right. right.
destruct l; simpl in HA|-*.
destruct HA as [H0 H1]. subst b0.
assert (lo + (hi - lo) = hi) by omega.
rewrite H in H1. clear H.
unfold inflate_free; simpl; rewrite resource_at_make_rmap.
specialize (PERM _ H1).
destruct (m_phi jm @ (b,z)) eqn:?; try destruct k; inv PERM.
if_tac in H0; inv H0.
rewrite if_true by (split; auto; omega).
right.
exists m, p0.
unfold perm_of_sh in H0.
repeat if_tac in H0; inv H0.
apply top_pfullshare in H. subst.
split; reflexivity.
* (* ~adr_range *)
destruct l.
destruct (free_nadr_range_eq _ _ _ _ _ _ _ HA FREE).
left.
unfold inflate_free; rewrite level_make_rmap; rewrite resource_at_make_rmap.
rewrite if_false by auto.
generalize (juicy_mem_contents jm); intro Hc.
generalize (juicy_mem_access jm (b0,z)); intro Ha.
rewrite resource_at_approx.
case_eq (m_phi jm @ (b0, z)); intros; rewrite H1 in Ha; auto.
Qed.

Lemma juicy_store_nodecay:
  forall jm m' ch b ofs v
       (H: store ch (m_dry jm) b ofs v = Some m')
          (PERM: forall z, ofs <= z < ofs + size_chunk ch ->
                      perm_order'' (perm_of_res (m_phi jm @ (b,z))) (Some Writable)),
       resource_nodecay (nextblock (m_dry jm)) (m_phi jm) (m_phi (store_juicy_mem jm _ _ _ _ _ H)).
Proof.
 intros.
 eapply inflate_store_resource_nodecay; eauto.
Qed.

Lemma can_age1_juicy_mem: forall j r,
  age (m_phi j) r -> exists j', age1 j = Some j'.
Proof.
intros j r H.
unfold age in H.
case_eq (age1_juicy_mem j); intros.
destruct (age1_juicy_mem_unpack _ _ H0).
eexists; eauto.
apply age1_juicy_mem_None1 in H0.
rewrite H0 in H.
elimtype False; inversion H.
Qed.


Lemma can_age_jm:
  forall jm, age1 (m_phi jm) <> None -> exists jm', age jm jm'.
Proof.
 intro jm; case_eq (age1 (m_phi jm)); intros; try congruence.
 apply (can_age1_juicy_mem _ _ H).
Qed.


Lemma age_jm_dry: forall {jm jm'}, age jm jm' -> m_dry jm = m_dry jm'.
Proof. intros; destruct (age1_juicy_mem_unpack _ _ H); auto. 
Qed.

Lemma age_jm_phi: forall {jm jm'}, age jm jm' -> age (m_phi jm) (m_phi jm').
Proof. intros; destruct (age1_juicy_mem_unpack _ _ H); auto. 
Qed.

(** * Results about aging in juicy memory conherence properties *)

Lemma age1_YES'_1 {phi phi' l rsh sh k P} :
  age1 phi = Some phi' ->
  phi @ l = YES rsh sh k P ->
  (exists P, phi' @ l = YES rsh sh k P).
Proof.
  intros A E.
  apply (proj1 (age1_YES' phi phi' l rsh sh k A)).
  eauto.
Qed.

Lemma age1_YES'_2 {phi phi' l rsh sh k P} :
  age1 phi = Some phi' ->
  phi' @ l = YES rsh sh k P ->
  (exists P, phi @ l = YES rsh sh k P).
Proof.
  intros A E.
  apply (proj2 (age1_YES' phi phi' l rsh sh k A)).
  eauto.
Qed.

Lemma age1_PURE_2 {phi phi' l k P} :
  age1 phi = Some phi' ->
  phi' @ l = PURE k P ->
  (exists P, phi @ l = PURE k P).
Proof.
  intros A E.
  apply (proj2 (age1_PURE phi phi' l k A)).
  eauto.
Qed.

Lemma perm_of_res_age x y loc :
  age x y -> perm_of_res (x @ loc) = perm_of_res (y @ loc).
Proof.
  intros A.
  destruct (x @ loc) as [sh | rsh sh k p | k p] eqn:E.
  - destruct (age1_NO x y loc sh A) as [[]_]; eauto.
  - destruct (age1_YES' x y loc rsh sh k A) as [[p' ->] _]; eauto.
  - destruct (age1_PURE x y loc k A) as [[p' ->] _]; eauto.
Qed.

Lemma contents_cohere_age m : hereditary age (contents_cohere m).
Proof.
  intros x y E A.
  intros rsh sh v loc pp H.
  destruct (proj2 (age1_YES' _ _ loc rsh sh (VAL v) E)) as [pp' E'].
  now eauto.
  specialize (A rsh sh v loc _ E').
  destruct A as [A ->]. split; auto.
  apply (proj1 (age1_YES _ _ loc rsh sh (VAL v) E)) in E'.
  congruence.
Qed.

Lemma access_cohere_age m : hereditary age (access_cohere m).
Proof.
  intros x y E B.
  intros addr.
  destruct (age1_levelS _ _ E) as [n L].
  rewrite (B addr).
  apply perm_of_res_age, E.
Qed.

Lemma max_access_cohere_age m : hereditary age (max_access_cohere m).
Proof.
  intros x y E C.
  intros addr; specialize (C addr).
  destruct (y @ addr) as [sh | sh p k pp | k p] eqn:AT.
  - eapply (age1_NO x) in AT; auto.
    rewrite AT in C; auto.
  - destruct (age1_YES'_2 E AT) as [P Ex].
    rewrite Ex in C.
    auto.
  - destruct (age1_PURE_2 E AT) as [P Ex].
    rewrite Ex in C; auto.
Qed.

Lemma alloc_cohere_age m : hereditary age (alloc_cohere m).
Proof.
  intros x y E D.
  intros loc G; specialize (D loc G).
  eapply (age1_NO x); eauto.
Qed.


(** * Results in the opposite direction *)

Definition unage {A} {_:ageable A} x y := age y x.

Lemma unage_YES'_1 {phi phi' l rsh sh k P} :
  age1 phi' = Some phi ->
  phi @ l = YES rsh sh k P ->
  (exists P, phi' @ l = YES rsh sh k P).
Proof.
  intros A E.
  apply (proj2 (age1_YES' phi' phi l rsh sh k A)).
  eauto.
Qed.

Lemma unage_YES'_2 {phi phi' l rsh sh k P} :
  age1 phi' = Some phi ->
  phi' @ l = YES rsh sh k P ->
  (exists P, phi @ l = YES rsh sh k P).
Proof.
  intros A E.
  apply (proj1 (age1_YES' phi' phi l rsh sh k A)).
  eauto.
Qed.

Lemma unage_PURE_2 {phi phi' l k P} :
  age1 phi' = Some phi ->
  phi' @ l = PURE k P ->
  (exists P, phi @ l = PURE k P).
Proof.
  intros A E.
  apply (proj1 (age1_PURE phi' phi l k A)).
  eauto.
Qed.

Lemma contents_cohere_unage m : hereditary unage (contents_cohere m).
Proof.
  intros x y E A.
  intros rsh sh v loc pp H.
  destruct (proj1 (age1_YES' _ _ loc rsh sh (VAL v) E)) as [pp' E'].
  eauto.
  specialize (A rsh sh v loc _ E').
  destruct A as [A ->]. split; auto.
  apply (proj2 (age1_YES _ _ loc rsh sh (VAL v) E)) in E'.
  congruence.
Qed.

Lemma access_cohere_unage m : hereditary unage (access_cohere m).
Proof.
  intros x y E B.
  intros addr.
  destruct (age1_levelS _ _ E) as [n L].
  rewrite (B addr).
  symmetry.
  apply perm_of_res_age, E.
Qed.

Lemma max_access_cohere_unage m : hereditary unage (max_access_cohere m).
Proof.
  intros x y E C.
  intros addr; specialize (C addr).
  destruct (x @ addr) as [sh | sh p k pp | k p] eqn:AT.
  - eapply (age1_NO y) in AT; auto.
    rewrite AT; auto.
  - destruct (@age1_YES'_2 y x addr sh p k pp E AT) as [P ->].
    auto.
  - destruct (age1_PURE_2 E AT) as [P Ex].
    rewrite Ex; auto.
Qed.

Lemma alloc_cohere_unage m : hereditary unage (alloc_cohere m).
Proof.
  intros x y E D.
  intros loc G; specialize (D loc G).
  eapply (age1_NO y); eauto.
Qed.

Lemma juicy_mem_unage jm' : { jm | age jm jm' }.
Proof.
  pose proof (rmap_unage_age (m_phi jm')) as A.
  remember (rmap_unage (m_phi jm')) as phi.
  unshelve eexists (mkJuicyMem (m_dry jm') phi _ _ _ _).
  all: destruct jm' as [m phi' Co Ac Ma N]; simpl.
  - eapply contents_cohere_unage; eauto.
  - eapply access_cohere_unage; eauto.
  - eapply max_access_cohere_unage; eauto.
  - eapply alloc_cohere_unage; eauto.
  - apply age1_juicy_mem_unpack''; auto.
Qed.
