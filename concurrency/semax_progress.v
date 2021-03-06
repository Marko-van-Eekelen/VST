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
Require Import concurrency.sync_preds.
Require Import concurrency.join_lemmas.
Require Import concurrency.aging_lemmas.
Require Import concurrency.cl_step_lemmas.
Require Import concurrency.resource_decay_lemmas.
Require Import concurrency.resource_decay_join.
Require Import concurrency.semax_invariant.
Require Import concurrency.semax_simlemmas.

Set Bullet Behavior "Strict Subproofs".

(* Lemma resource_at_join_sub_inv (phi1 phi2 : rmap) : *)
(*   (forall l, join_sub (phi1 @ l) (phi2 @ l)) -> *)
(*   join_sub phi1 phi2. *)
(* Proof. *)
(* Qed. *)

Section Progress.
  Variables
    (CS : compspecs)
    (ext_link : string -> ident)
    (ext_link_inj : forall s1 s2, ext_link s1 = ext_link s2 -> s1 = s2).

  Definition Jspec' := (@OK_spec (Concurrent_Espec unit CS ext_link)).
  
  Open Scope string_scope.
  
  Theorem progress Gamma n state :
    state_invariant Jspec' Gamma (S n) state ->
    exists state',
      state_step state state'.
  Proof.
    intros I.
    inversion I as [m ge sch tp Phi En gam compat sparse lock_coh safety wellformed unique E]. rewrite <-E in *.
    destruct sch as [ | i sch ].
    
    (* empty schedule: we loop in the same state *)
    {
      exists state. subst. constructor.
    }
    
    destruct (ssrnat.leq (S i) tp.(ThreadPool.num_threads).(pos.n)) eqn:Ei; swap 1 2.
    
    (* bad schedule *)
    {
      eexists.
      (* split. *)
      (* -  *)constructor.
        apply JuicyMachine.schedfail with i.
        + reflexivity.
        + unfold ThreadPool.containsThread.
          now rewrite Ei; auto.
        + constructor.
        + reflexivity.
    }
    
    (* the schedule selected one thread *)
    assert (cnti : ThreadPool.containsThread tp i) by apply Ei.
    remember (ThreadPool.getThreadC cnti) as ci eqn:Eci; symmetry in Eci.
    
    destruct ci as
        [ (* Krun *) ci
        | (* Kblocked *) ci
        | (* Kresume *) ci v
        | (* Kinit *) v1 v2 ].
    
    (* thread[i] is running *)
    {
      pose (jmi := jm_ cnti compat).
      (* pose (phii := m_phi jmi). *)
      (* pose (mi := m_dry jmi). *)
      
      destruct ci as [ve te k | ef sig args lid ve te k] eqn:Heqc.
      
      (* thread[i] is running and some internal step *)
      {
        (* get the next step of this particular thread (with safety for all oracles) *)
        assert (next: exists ci' jmi',
                   corestep (juicy_core_sem cl_core_sem) ge ci jmi ci' jmi'
                   /\ forall ora, jsafeN Jspec' ge n ora ci' jmi').
        {
          specialize (safety i cnti).
          pose proof (safety tt) as safei.
          rewrite Eci in *.
          inversion safei as [ | ? ? ? ? c' m' step safe H H2 H3 H4 | | ]; subst.
          2: now match goal with H : at_external _ _ = _ |- _ => inversion H end.
          2: now match goal with H : halted _ _ = _ |- _ => inversion H end.
          exists c', m'. split; [ apply step | ].
          revert step safety safe; clear.
          generalize (jm_ cnti compat).
          generalize (State ve te k).
          unfold jsafeN.
          intros c j step safety safe ora.
          eapply safe_corestep_forward.
          - apply juicy_core_sem_preserves_corestep_fun.
            apply semax_lemmas.cl_corestep_fun'.
          - apply step.
          - apply safety.
        }
        
        destruct next as (ci' & jmi' & stepi & safei').
        pose (tp' := age_tp_to (level jmi') tp).
        pose (tp'' := @ThreadPool.updThread i tp' (cnt_age' cnti) (Krun ci') (m_phi jmi')).
        pose (cm' := (m_dry jmi', ge, (i :: sch, tp''))).
        exists cm'.
        apply state_step_c; [].
        apply JuicyMachine.thread_step with
        (tid := i)
          (ev := nil)
          (Htid := cnti)
          (Hcmpt := mem_compatible_forget compat); [|]. reflexivity.
        eapply step_juicy; [ | | | | | ].
        + reflexivity.
        + now constructor.
        + exact Eci. 
        + destruct stepi as [stepi decay].
          split.
          * simpl.
            subst.
            unfold SEM.Sem in *.
            rewrite SEM.CLN_msem.
            apply stepi.
          * simpl.
            exact_eq decay.
            reflexivity.
        + reflexivity.
        + reflexivity.
      }
      (* end of internal step *)
      
      (* thread[i] is running and about to call an external: Krun (at_ex c) -> Kblocked c *)
      {
        eexists.
        (* taking the step *)
        constructor.
        eapply JuicyMachine.suspend_step.
        + reflexivity.
        + reflexivity.
        + eapply mem_compatible_forget; eauto.
        + econstructor.
          * eassumption.
          * unfold SEM.Sem in *.
            rewrite SEM.CLN_msem.
            reflexivity.
          * constructor.
          * reflexivity.
      } (* end of Krun (at_ex c) -> Kblocked c *)
    } (* end of Krun *)
    
    (* thread[i] is in Kblocked *)
    {
      (* goes to Kresume ci' according to the rules of syncStep  *)
      
      destruct ci as [ve te k | ef sig args lid ve te k] eqn:Heqc.
      
      (* internal step: impossible, because in state Kblocked *)
      {
        exfalso.
        pose proof (wellformed i cnti) as W.
        rewrite Eci in W.
        apply W.
        reflexivity.
      }
      (* back to external step *)
      
      (* paragraph below: ef has to be an EF_external *)
      assert (Hef : match ef with EF_external _ _ => Logic.True | _ => False end).
      {
        pose proof (safety i cnti tt) as safe_i.
        rewrite Eci in safe_i.
        inversion safe_i; subst; [ now inversion H0; inversion H | | now inversion H ].
        inversion H0; subst; [].
        match goal with x : ext_spec_type _ _  |- _ => clear -x end.
        now destruct e eqn:Ee; [ apply I | .. ];
          simpl in x;
          repeat match goal with
                   _ : context [ oi_eq_dec ?x ?y ] |- _ =>
                   destruct (oi_eq_dec x y); try discriminate; try tauto
                 end.
      }
      assert (Ex : exists name sig, ef = EF_external name sig) by (destruct ef; eauto; tauto).
      destruct Ex as (name & sg & ->); clear Hef.
      
      (* paragraph below: ef has to be an EF_external with one of those 5 names *)
      assert (which_primitive :
                Some (ext_link "acquire") = (ef_id ext_link (EF_external name sg)) \/
                Some (ext_link "release") = (ef_id ext_link (EF_external name sg)) \/
                Some (ext_link "makelock") = (ef_id ext_link (EF_external name sg)) \/
                Some (ext_link "freelock") = (ef_id ext_link (EF_external name sg)) \/
                Some (ext_link "spawn") = (ef_id ext_link (EF_external name sg))).
      {
        pose proof (safety i cnti tt) as safe_i.
        rewrite Eci in safe_i.
        inversion safe_i; subst; [ now inversion H0; inversion H | | now inversion H ].
        inversion H0; subst; [].
        match goal with H : ext_spec_type _ _  |- _ => clear -H end.
        simpl in *.
        repeat match goal with
                 _ : context [ oi_eq_dec ?x ?y ] |- _ =>
                 destruct (oi_eq_dec x y); try injection e; auto
               end.
        tauto.
      }
      
      (* Before going any further, one needs to provide the first
        rmap of the oracle.  Unfortunately, for that, we need to know
        whether we're in an "acquire" external call or not. In
        addition, in the case of an "acquire" we need to know the
        arguments of the function (address+mpred) so that we can
        provide the right rmap from the lock set.
        |
        Two solutions: either we use a dummy oracle to know those things (but
        ... we need the oracle before that (FIX the spec OR [A]), or we write
        it as a P\/~P and then we derive a contradiction (not sure we can do
        that). *)
      
      destruct which_primitive as
          [ H_acquire | [ H_release | [ H_makelock | [ H_freelock | H_spawn ] ] ] ].
      
      { (* the case of acquire *)
        
        (* using the safety to prepare the precondition *)
        pose proof (safety i cnti tt) as safei.
        rewrite Eci in safei.
        unfold jsafeN, juicy_safety.safeN in safei.
        inversion safei
          as [ | ?????? bad | n0 z c m0 e sig0 args0 x at_ex Pre SafePost | ????? bad ];
          [ now inversion bad; inversion H | subst | now inversion bad ].
        subst.
        simpl in at_ex. injection at_ex as <- <- <- .
        hnf in x.
        revert x Pre SafePost.
        
        Local Notation "{| 'JE_spec ... |}" := {| JE_spec := _; JE_pre_hered := _; JE_post_hered := _; JE_exit_hered := _ |}.
        
        (* dependent destruction *)
        funspec_destruct "acquire".
        
        intros (phix, ((vx, shx), Rx)) Pre. simpl in Pre.
        destruct Pre as (phi0 & phi1 & Join & Precond & HnecR).
        simpl (and _).
        intros Post.
        
        (* relate lset to val *)
        destruct Precond as [PREA [[PREB _] PREC]].
        hnf in PREB.
        unfold canon.SEPx in PREC.
        simpl in PREC.
        rewrite seplog.sepcon_emp in PREC.
        pose proof PREC as islock.
        apply lock_inv_at in islock.
        
        assert (SUB : join_sub phi0 Phi). {
          apply join_sub_trans with  (ThreadPool.getThreadR cnti).
          - econstructor; eauto.
          - apply compatible_threadRes_sub; eauto.
            destruct compat; eauto.
        }
        destruct islock as [b [ofs [-> [R islock]]]].
        pose proof (resource_at_join_sub _ _ (b, Int.unsigned ofs) SUB) as SUB'.
        pose proof islock_pred_join_sub SUB' islock as isl.
        
        (* PLAN
           - DONE: integrate the oracle in the semax_conc definitions
           - DONE: sort out this dependent type problem
           - DONE: exploit jsafeN_ to figure out which possible cases
           - DONE: push the analysis through Krun/Kblocked/Kresume
           - DONE: figure a wait out of the ext_link problem (the LOCK
             should be a parameter of the whole thing)
           - DONE: change the lock_coherence invariants to talk about
             Mem.load instead of directly reading the values, since
             this will be abstracted
           - TODO: acquire-fail: still problems (see below)
           - DONE: acquire-success: the invariant guarantees that the
             rmap in the lockset satisfies the invariant.  We can give
             this rmap as a first step to the oracle.  We again have
             to recover the fact that all oracles after this step will
             be fine as well.
           - TODO: spawning: it introduces a new Kinit, change
             invariant accordingly
           - TODO release: this time, the jsafeN_ will explain how to
             split the current rmap.
         *)
        
          
        (* next step depends on status of lock: *)
        pose proof (lock_coh (b, Int.unsigned ofs)) as lock_coh'.
        destruct (AMap.find (elt:=option rmap) (b, Int.unsigned ofs) (ThreadPool.lset tp))
          as [[unlockedphi|]|] eqn:Efind;
          swap 1 3.
        (* inversion lock_coh' as [wetv dryv notlock H H1 H2 | R0 wetv isl' Elockset Ewet Edry | R0 phi wetv isl' SAT_R_Phi Elockset Ewet Edry]. *)
        
        - (* None: that cannot be: there is no lock at that address *)
          exfalso.
          destruct isl as [x [? [? EPhi]]].
          rewrite EPhi in lock_coh'.
          rewrite <-isLKCT_rewrite in lock_coh'.
          eapply (proj1 (lock_coh' _ _ _ _)).
          reflexivity.
        
        - (* Some None: lock is locked, so [acquire] fails. *)
          destruct lock_coh' as [LOAD (sh' & R' & lk)].
          destruct isl as [sh [psh [z Ewetv]]].
          rewrite Ewetv in *.
          
          (* rewrite Eat in Ewetv. *)
          specialize (lk (b, Int.unsigned ofs)).
          rewrite jam_true in lk; swap 1 2.
          { hnf. unfold lock_size in *; split; auto; omega. }
          rewrite jam_true in lk; swap 1 2. now auto.
          
          unfold lock_inv in PREC.
          destruct PREC as (b0 & ofs0 & EQ & LKSPEC).
          injection EQ as <- <-.
          exists (m, ge, (sch, tp))(* ; split *).
          + apply state_step_c.
            apply JuicyMachine.sync_step with
            (Htid := cnti)
              (Hcmpt := mem_compatible_forget compat)
              (ev := Events.failacq (b, Int.intval (* replace with unsigned? *) ofs));
              [ reflexivity (* schedPeek *)
              | reflexivity (* schedSkip *)
              | ].
            
            (* factoring proofs out before the inversion/eapply *)
            specialize (LKSPEC (b, Int.unsigned ofs)).
            simpl in LKSPEC.
            if_tac in LKSPEC; swap 1 2.
            { destruct H.
              unfold lock_size; simpl.
              split. reflexivity. omega. }
            if_tac in LKSPEC; [ | congruence ].
            destruct LKSPEC as (p & E).
            pose proof (resource_at_join _ _ _ (b, Int.unsigned ofs) Join) as J.
            rewrite E in J.
            
            assert (Ename : name = "acquire"). {
              simpl in *.
              injection H_acquire as Ee.
              apply ext_link_inj in Ee; auto.
            }
            
            assert (Ez : z = LKSIZE). {
              simpl in lk.
              destruct lk as [psh' EPhi].
              rewrite EPhi in Ewetv.
              injection Ewetv as _ _ <-.
              reflexivity.
            }
            
            assert (Ecall: Some (EF_external name sg, sig, args) =
                           Some (LOCK, UNLOCK_SIG, Vptr b ofs :: nil)). {
              repeat f_equal.
              - auto.
              - 
                Unset Printing Notations.
                admit.
              - admit.
                 (* design decision:
                    - we can make 'safety' imply wellformedness of this signature
                    - or we can add wellformed as an hypothesis of the program *)
                 (* see with andrew: should safety require signatures
                 to be exactly something?  Maybe it should be in
                 ext_spec_type, it'd be easy, maybe. *)
              - assert (L: length args = 1%nat) by admit.
                (* TODO discuss with andrew for where to add this requirement *)
                clear -PREB L.
                unfold expr.eval_id in PREB.
                unfold expr.force_val in PREB.
                match goal with H : context [Map.get ?a ?b] |- _ => destruct (Map.get a b) eqn:E end.
                subst v. 2: discriminate.
                pose  (gx := (filter_genv (symb2genv (Genv.genv_symb ge)))). fold gx in E.
                destruct args as [ | arg [ | ar args ]].
                + now inversion E.
                + inversion E. reflexivity.
                + inversion E. f_equal.
                  inversion L.
            }
            
            assert (Eae : at_external SEM.Sem (ExtCall (EF_external name sg) sig args lid ve te k) =
                    Some (LOCK, ef_sig LOCK, Vptr b ofs :: nil)). {
              simpl.
              unfold SEM.Sem in *.
              rewrite SEM.CLN_msem; simpl.
              repeat f_equal; congruence.
            }
            
            inversion J; subst.
            
            * eapply step_acqfail with (Hcompatible := mem_compatible_forget compat)
                                       (R := approx (level phi0) (Interp Rx)).
              all: try solve [ constructor | eassumption | reflexivity ];
                [ > idtac ].
              simpl.
              unfold Int.unsigned in *.
              rewrite <-H7.
              reflexivity.
            
            * eapply step_acqfail with (Hcompatible := mem_compatible_forget compat)
                                       (R := approx (level phi0) (Interp Rx)).
              all: try solve [ constructor | eassumption | reflexivity ];
                [ > idtac ].
              simpl.
              unfold Int.unsigned in *.
              rewrite <-H7.
              reflexivity.
        
        - (* acquire succeeds *)
          destruct isl as [sh [psh [z Ewetv]]].
          destruct lock_coh' as [LOAD (sh' & R' & lk & sat)].
          rewrite Ewetv in *.
          
          unfold lock_inv in PREC.
          destruct PREC as (b0 & ofs0 & EQ & LKSPEC).
          injection EQ as <- <-.
          
          specialize (lk (b, Int.unsigned ofs)).
          rewrite jam_true in lk; swap 1 2.
          { hnf. unfold lock_size in *; split; auto; omega. }
          rewrite jam_true in lk; swap 1 2. now auto.
          destruct sat as [sat | sat]; [ | omega ].
          
          (* changing value of lock in dry mem *)
          Unset Printing Implicit.
          assert (Hm' : exists m', Mem.store Mint32 (restrPermMap (mem_compatible_locks_ltwritable (mem_compatible_forget compat))) b (Int.intval ofs) (Vint Int.zero) = Some m'). {
            Transparent Mem.store.
            unfold Mem.store in *.
            destruct (Mem.valid_access_dec _ Mint32 b (Int.intval ofs) Writable) as [N|N].
            now eauto.
            exfalso.
            apply N; clear -Efind lock_coh.
            eapply lset_valid_access; eauto.
            unfold Int.unsigned in *.
            congruence.
          }
          destruct Hm' as (m', Hm').
          
          
          (* joinability condition provided by invariant : phi' will
          be the thread's new rmap *)
          destruct (compatible_threadRes_lockRes_join (mem_compatible_forget compat) cnti _ Efind)
            as (phi', Jphi').
          
          (*
          (* to build the new dry memory I need to use [restrPermMap]
          which requires [mem_compatible tp''' m']. Then I have to
          prove all the coherence things again, one of being
          [lockSet_Writable], which is NOT true. So I must use
          something else. *)
          
          (* This is silly, there is no reason that this must be a
          juicy mem. *)
          
          match goal with
            _ : _ = Kblocked ?c |- _ => pose c end.
          pose (tp' := updThread cnti (Kresume c Vundef) phi').
          pose (tp'' := updLockSet tp' (b, Int.intval ofs) None).
          pose (tp''' := age_tp_to (level phi' - 1) tp'').
          pose (Phi' := age_to (level Phi - 1) Phi).
          
          assert (MC : mem_compatible_with tp''' m' Phi'). {
            constructor.
            - unfold tp''' in *.
              unfold Phi' in *.
              replace (level phi') with (level Phi) by (join_level_tac; cleanup; congruence).
              apply join_all_age_to. cleanup; omega.
              unfold tp'' in *.
              rewrite join_all_joinlist.
              rewrite maps_updlock1.
              unfold tp' in *.
              rewrite maps_remLockSet_updThread.
              rewrite maps_updthread.
              pose proof juice_join compat as j.
              rewrite join_all_joinlist in j.
              rewrite (maps_getlock3 _ _ _ Efind) in j.
              assert (cnti': containsThread (remLockSet tp (b, Int.unsigned ofs)) i) by auto.
              rewrite maps_getthread with (i := i) (cnti := cnti') in j.
              revert j.
              apply joinlist_merge.
              apply join_comm.
              exact_eq Jphi'; f_equal.
              destruct tp. simpl. f_equal. f_equal. apply proof_irr.
            
            - (* pfdf. *)
              admit.
            
            - unfold tp''' in *.
              apply lockSet_Writable_age.
              unfold tp'' in *.
              Lemma lockSet_Writable_updLockSet tp loc m o :
                lockRes tp loc <> None ->
                lockSet_Writable (lset tp) m ->
                lockSet_Writable (lset (updLockSet tp loc o)) m.
              Proof.
                unfold lockSet_Writable in *.
                unfold lockRes in *.
                cleanup.
                intros F H b ofs E.
                apply (H b ofs).
                destruct tp; simpl in *.
                rewrite AMap_find_add in E.
                unfold AMap.key in *.
                destruct (eq_dec loc (b, ofs)); [ | now auto ].
                subst. cleanup.
                destruct ( AMap.find (elt:=option rmap) (b, ofs) lset0). reflexivity. tauto.
              Qed.
              apply lockSet_Writable_updLockSet.
              { cleanup.
                unfold Int.unsigned in *.
                unfold tp' in *.
                simpl.
                rewrite Efind.
                congruence. }
              unfold tp' in *.
              simpl.
              (* NOW I have to prove [lockSet_Writable (lset tp) m']
              which is not true at all. *)
              admit.
            - admit.
            - admit.
          }
          clear MC (* was not true *).
          *)
          
          (* NOT
          (* somehow the new mem and the Phi has to be a juicy memory
          -> it does NOT. The requirement will be removed from the
          juicy machine *)
          assert (Hjm' : exists jm', m_dry jm' = m' /\ m_phi jm' = phi'). {
            unshelve eexists (mkJuicyMem m' phi' _ _ _ _); [ .. | auto ].
            - Require Import veric.juicy_mem_lemmas.
              apply contents_cohere_join_sub with Phi; [ | now join_sub_tac ].
              assert (C : contents_cohere m Phi) by apply compat.
              intros rsh sh0 v loc pp H.
              specialize (C rsh sh0 v loc pp H).
              destruct C as [C ?]; split; auto.
              pose proof store_outside' _ _ _ _ _ _ Hm' as SO.
              destruct SO as (SO & _).
              destruct loc as (b', ofs').
              specialize (SO b' ofs').
              destruct SO as [SO | SO].
              + exfalso.
                admit (* cannot be YES *).
              + rewrite <-SO.
                rewrite restrPermMap_contents.
                auto.
            - (* this shouldn't be m', but some restrPermMap *)
              Lemma contents_cohere_join_sub m phi1 phi2 :
                join_sub phi1 phi2 ->
                contents_cohere m phi2 ->
                contents_cohere m phi1.
              Admitted.
              (* intros rsh sh0 v loc pp E. *)
              admit.
            - admit.
            - admit.
          }
          destruct Hjm' as (jm', Hjm').
          *)
          
          (* necessary to know that we have indeed a lock *)
          assert (ex: exists sh0 psh0, phi0 @ (b, Int.intval ofs) = YES sh0 psh0 (LK LKSIZE) (pack_res_inv (approx (level phi0) (Interp Rx)))). {
            clear -LKSPEC.
            specialize (LKSPEC (b, Int.intval ofs)).
            simpl in LKSPEC.
            if_tac in LKSPEC. 2:range_tac.
            if_tac in LKSPEC. 2:tauto.
            destruct LKSPEC as (p, E).
            do 2 eexists.
            apply E.
          }
          destruct ex as (sh0 & psh0 & ex).
          pose proof (resource_at_join _ _ _ (b, Int.intval ofs) Join) as Join'.
          destruct (join_YES_l Join' ex) as (sh3 & sh3' & E3).
          
          eexists (m', ge, (sch, _)).
          + (* taking the step *)
            apply state_step_c.
            apply JuicyMachine.sync_step
            with (ev := (Events.acquire (b, Int.intval ofs) None))
                   (tid := i)
                   (Htid := cnti)
                   (Hcmpt := mem_compatible_forget compat)
            ;
              [ reflexivity | reflexivity | ].
            eapply step_acquire
            with (R := approx (level phi0) (Interp Rx))
            (* with (sh := shx) *)
            .
            all: try match goal with |- _ = age_tp_to _ _ => reflexivity end.
            all: try match goal with |- _ = updLockSet _ _ _ => reflexivity end.
            all: try match goal with |- _ = updThread _ _ _ => reflexivity end.
            * now auto.
            * eassumption.
            * simpl.
              unfold SEM.Sem in *.
              rewrite SEM.CLN_msem.
              simpl.
              repeat f_equal; [ | | | ].
              -- simpl in H_acquire.
                 injection H_acquire as Ee.
                 apply ext_link_inj in Ee.
                 rewrite <-Ee.
                 reflexivity.
              -- admit (* same problem above *).
              -- admit (* same problem above *).
              -- admit (* same problem above *).
            * reflexivity.
            * unfold fold_right in *.
              rewrite E3.
              f_equal.
            * reflexivity.
            * apply LOAD.
            * apply Hm'.
            * apply Efind.
            * apply Jphi'.
      }

      { (* the case of release *)

        (* using the safety to prepare the precondition *)
        pose proof (safety i cnti tt) as safei.
        rewrite Eci in safei.
        unfold jsafeN, juicy_safety.safeN in safei.
        inversion safei
          as [ | ?????? bad | n0 z c m0 e sig0 args0 x at_ex Pre SafePost | ????? bad ];
          [ now inversion bad; inversion H | subst | now inversion bad ].
        subst.
        simpl in at_ex. injection at_ex as <- <- <- .
        hnf in x.
        revert x Pre SafePost.
        
        (* dependent destruction *)
        funspec_destruct "acquire".
        funspec_destruct "release".
        
        intros (phix, ((vx, shx), Rx)) Pre. simpl in Pre.
        destruct Pre as (phi0 & phi1 & Join & Precond & HnecR).
        simpl (and _).
        intros Post.
        
        (* relate lset to val *)
        destruct Precond as [PREA [[PREB _] PREC]].
        hnf in PREB.
        unfold canon.SEPx in PREC.
        simpl in PREC.
        rewrite seplog.sepcon_emp in PREC.
        destruct PREC as (phi_lockinv & phi_sat & jphi & Hlockinv & SAT).
        pose proof Hlockinv as islock.
        apply lock_inv_at in islock.
        
        assert (SUB : join_sub phi_lockinv Phi). {
          apply join_sub_trans with phi0. econstructor; eauto.
          apply join_sub_trans with (getThreadR cnti). econstructor; eauto.
          apply compatible_threadRes_sub; eauto. apply compat.
        }
        destruct islock as [b [ofs [-> [R islock]]]].
        pose proof (resource_at_join_sub _ _ (b, Int.unsigned ofs) SUB) as SUB'.
        pose proof islock_pred_join_sub SUB' islock as isl.
        
        (* next step depends on status of lock: *)
        pose proof (lock_coh (b, Int.unsigned ofs)) as lock_coh'.
        destruct (AMap.find (elt:=option rmap) (b, Int.unsigned ofs) (ThreadPool.lset tp))
          as [[unlockedphi|]|] eqn:Efind;
          swap 1 3.
        
        - (* None: that cannot be: there is no lock at that address *)
          exfalso.
          destruct isl as [x [? [? EPhi]]].
          rewrite EPhi in lock_coh'.
          rewrite <-isLKCT_rewrite in lock_coh'.
          eapply (proj1 (lock_coh' _ _ _ _)).
          reflexivity.
        
        - (* Some None: lock is locked, so [release] should succeed. *)
          destruct lock_coh' as [LOAD (sh' & R' & lk)].
          destruct isl as [sh [psh [z Ewetv]]].
          rewrite Ewetv in *.
          
          (* rewrite Eat in Ewetv. *)
          specialize (lk (b, Int.unsigned ofs)).
          rewrite jam_true in lk; swap 1 2.
          { hnf. unfold lock_size in *; split; auto; omega. }
          rewrite jam_true in lk; swap 1 2. now auto.
          
          assert (Ename : name = "release"). {
            simpl in *.
            injection H_release as Ee.
            apply ext_link_inj in Ee; auto.
          }
          
          assert (Ez : z = LKSIZE). {
            simpl in lk.
            destruct lk as [psh' EPhi].
            rewrite EPhi in Ewetv.
            injection Ewetv as _ _ <-.
            reflexivity.
          }
          
          assert (Ecall: Some (EF_external name sg, sig, args) =
                         Some (UNLOCK, UNLOCK_SIG, Vptr b ofs :: nil)). {
            admit.
            (* same problem as above. *)
            (* repeat f_equal; auto. *)
          }
          
          assert (Eae : at_external SEM.Sem (ExtCall (EF_external name sg) sig args lid ve te k) =
                        Some (UNLOCK, ef_sig UNLOCK, Vptr b ofs :: nil)). {
            simpl.
            unfold SEM.Sem in *.
            rewrite SEM.CLN_msem; simpl.
            auto.
          }
          subst z.
          
          assert (E1: exists sh sh', getThreadR cnti @ (b, Int.intval ofs) = YES sh sh' (LK LKSIZE) (pack_res_inv R)).
          {
            revert Join jphi SUB' islock; clear.
            unfold Int.unsigned in *.
            generalize (b, Int.intval ofs); intros l. clear b ofs.
            intros A B (r, C).
            apply resource_at_join with (loc := l) in A.
            apply resource_at_join with (loc := l) in B.
            unfold islock_pred in *.
            intros (sh1 & sh1' & z & E).
            rewr (phi_lockinv @ l) in C; inv C;
              rewr (phi_lockinv @ l) in B; inv B;
                rewr (phi0 @ l) in A; inv A;
                  eauto.
          }
          destruct E1 as (sh1 & sh1' & E1).
          
          assert (Hm' : exists m', Mem.store Mint32 (restrPermMap (mem_compatible_locks_ltwritable (mem_compatible_forget compat))) b (Int.intval ofs) (Vint Int.one) = Some m').
          {
            unfold Mem.store in *.
            destruct (Mem.valid_access_dec _ Mint32 b (Int.intval ofs) Writable) as [N|N].
            now eauto.
            exfalso.
            apply N; clear -Efind lock_coh.
            eapply lset_valid_access; eauto.
            unfold Int.unsigned in *.
            congruence.
          }
          destruct Hm' as (m', Hm').
          
          (* remove [phi_sat] from [getThreadR cnti] to get the new [phi'] *)
          assert (Hphi' : exists phi',
                     join phi_lockinv phi1 phi' /\
                     join phi' phi_sat (getThreadR cnti)). {
            repeat match goal with H : join _ _ _ |- _ => revert H end; clear; intros.
            apply join_comm in jphi.
            destruct (sepalg.join_assoc jphi Join) as (phi' & j1 & j2).
            eauto.
          }
          destruct Hphi' as (phi' & Ephi' & Join_with_sat).
          
          assert (Sat : R (age_by 1 phi_sat)). {
            clear Post Hm' safei PREA Eci Heq_name Heq_name0 LOAD Eae.
            apply predat4 in Hlockinv.
            apply predat5 in islock.
            pose proof predat_inj islock Hlockinv.
            subst R.
            split.
            - rewrite level_age_by.
              replace (level phi_sat) with (level Phi) by join_level_tac.
              replace (level phi_lockinv) with (level Phi) by join_level_tac.
              omega.
            - hered. 2: apply pred_hered.
              apply age_by_1. replace (level phi_sat) with (level Phi). omega. join_level_tac.
          }
          
          (* m' and phi' are NOT a not a juicy mem *)
          (*
          (* somehow the new mem and the Phi has to be a juicy memory *)
          assert (Hjm' : exists jm', m_dry jm' = m' /\ m_phi jm' = phi'). {
            admit (* ask santiago if he can provide such coherence results on restrPermMap *).
            (*unshelve eexists.
            unshelve refine (mkJuicyMem m' phi' _ _ _ _).
            all: try (split; reflexivity).
             *)
          }
          destruct Hjm' as (jm' & <- & <-).
          *)
          
          eexists (m', ge, (sch, _)).
          eapply state_step_c.
          eapply JuicyMachine.sync_step with (Htid := cnti); auto.
          eapply step_release
          with (c := (ExtCall (EF_external name sg) sig args lid ve te k))
                 (Hcompatible := mem_compatible_forget compat);
              try apply Eci;
            try apply Eae;
            try apply Eci;
            try apply LOAD;
            try apply Hm';
            try apply E1;
            try eapply join_comm, Join_with_sat;
            try apply Wjm';
            try apply Sat;
            try apply Efind;
            try reflexivity.
        
        - (* Some Some: lock is unlocked, this should be impossible *)
          destruct lock_coh' as [LOAD (sh' & R' & lk & sat)].
          destruct sat as [sat | ?]; [ | congruence ].
          destruct isl as [sh [psh [z Ewetv]]].
          rewrite Ewetv in *.
          exfalso.
          clear Post.
          
          (* sketch: *)
          (* - [unlockedphi] satisfies R *)
          (* - [phi_sat] satisfies R *)
          (* - [unlockedphi] and [phi_sat] join *)
          (* - but R is positive and precise so that's impossible *)
          simpl in PREA.
          destruct PREA as (Hreadable & Hprecise & Hpositive & []).
          
          pose proof predat3 lk as E1.
          pose proof predat1 Ewetv as E2.
          pose proof predat4 Hlockinv as E3.
          apply (predat_join_sub SUB) in E3.
          assert (level phi_lockinv = level Phi) by apply join_sub_level, SUB.
          assert (level unlockedphi = level Phi).
          { eapply join_sub_level, compatible_lockRes_sub; eauto; apply compat. }
          rewr (level phi_lockinv) in E3.
          assert (join_sub phi_sat Phi). {
            apply join_sub_trans with phi0. hnf; eauto.
            apply join_sub_trans with (getThreadR cnti). hnf; eauto.
            apply compatible_threadRes_sub. apply compat.
          }
          assert (level phi_sat = level Phi) by (apply join_sub_level; auto).
          
          pose proof positive_precise_joins_false
               (approx (level Phi) R) (age_by 1 unlockedphi) (age_by 1 phi_sat) as PP.
          apply PP.
          + (* positive *)
            apply positive_approx with (n := level Phi) in Hpositive.
            exact_eq Hpositive; f_equal.
            eapply predat_inj; eauto.
          
          + (* precise *)
            unfold approx.
            apply precise_approx with (n := level Phi) in Hprecise.
            exact_eq Hprecise; f_equal.
            eapply predat_inj; eauto.
          
          + (* sat 1 *)
            split.
            * rewrite level_age_by. rewr (level unlockedphi). omega.
            * revert sat.
              apply approx_eq_app_pred with (level Phi).
              -- rewrite level_age_by. rewr (level unlockedphi). omega.
              -- eapply predat_inj; eauto.
          
          + (* sat 2 *)
            split.
            -- rewrite level_age_by. rewr (level phi_sat). omega.
            -- cut (app_pred (Interp Rx) (age_by 1 phi_sat)).
               ++ apply approx_eq_app_pred with (S n).
                  ** rewrite level_age_by. rewr (level phi_sat). omega.
                  ** pose proof (predat_inj E3 E2) as G.
                     exact_eq G; do 2 f_equal; auto.
               ++ revert SAT. apply age_by_ind.
                  destruct (Interp Rx).
                  auto.
          
          + (* joins *)
            apply age_by_joins.
            apply joins_sym.
            eapply @join_sub_joins_trans with (c := phi0); auto. apply Perm_rmap.
            * exists phi_lockinv. apply join_comm. auto.
            * eapply @join_sub_joins_trans with (c := getThreadR cnti); auto. apply Perm_rmap.
              -- exists phi1. auto.
              -- eapply compatible_threadRes_lockRes_join. apply (mem_compatible_forget compat).
                 apply Efind.
      }
      
      { (* the case of makelock *)

        (* using the safety to prepare the precondition *)
        pose proof (safety i cnti tt) as safei.
        rewrite Eci in safei.
        unfold jsafeN, juicy_safety.safeN in safei.
        inversion safei
          as [ | ?????? bad | n0 z c m0 e sig0 args0 x at_ex Pre SafePost | ????? bad ];
          [ now inversion bad; inversion H | subst | now inversion bad ].
        subst.
        simpl in at_ex. injection at_ex as <- <- <- .
        hnf in x.
        revert x Pre SafePost.
        
        (* dependent destruction *)
        funspec_destruct "acquire".
        funspec_destruct "release".
        funspec_destruct "makelock".
        
        intros (phix, ((vx, shx), Rx)) Pre. simpl in Pre.
        destruct Pre as (phi0 & phi1 & Join & Precond & HnecR).
        simpl (and _).
        intros Post.
        
        admit.
      }
      
      { (* the case of makelock *)

        (* using the safety to prepare the precondition *)
        pose proof (safety i cnti tt) as safei.
        rewrite Eci in safei.
        unfold jsafeN, juicy_safety.safeN in safei.
        inversion safei
          as [ | ?????? bad | n0 z c m0 e sig0 args0 x at_ex Pre SafePost | ????? bad ];
          [ now inversion bad; inversion H | subst | now inversion bad ].
        subst.
        simpl in at_ex. injection at_ex as <- <- <- .
        hnf in x.
        revert x Pre SafePost.
        
        (* dependent destruction *)
        funspec_destruct "acquire".
        funspec_destruct "release".
        funspec_destruct "makelock".
        funspec_destruct "freelock".
        admit.
      }
      
      { (* the case of makelock *)

        (* using the safety to prepare the precondition *)
        pose proof (safety i cnti tt) as safei.
        rewrite Eci in safei.
        unfold jsafeN, juicy_safety.safeN in safei.
        inversion safei
          as [ | ?????? bad | n0 z c m0 e sig0 args0 x at_ex Pre SafePost | ????? bad ];
          [ now inversion bad; inversion H | subst | now inversion bad ].
        subst.
        simpl in at_ex. injection at_ex as <- <- <- .
        hnf in x.
        revert x Pre SafePost.
        
        (* dependent destruction *)
        funspec_destruct "acquire".
        funspec_destruct "release".
        funspec_destruct "makelock".
        funspec_destruct "freelock".
        funspec_destruct "spawn".
        admit.
        (* no obligation after "release" yet *)
      }
    }
    (* end of Kblocked *)
    
    (* thread[i] is in Kresume *)
    {
      (* goes to Krun ci' with after_ex ci = ci'  *)
      destruct ci as [ve te k | ef sig args lid ve te k] eqn:Heqc.
      
      - (* contradiction: has to be an extcall *)
        specialize (wellformed i cnti).
        rewrite Eci in wellformed.
        simpl in wellformed.
        tauto.
      
      - (* extcall *)
        pose (ci':=
                match lid with
                | Some id => State ve (Maps.PTree.set id (Vint Int.zero) te) k
                | None => State ve te k
                end).
        exists (m, ge, (i :: sch, ThreadPool.updThreadC cnti (Krun ci')))(* ; split *).
        + (* taking the step Kresum->Krun *)
          constructor.
          apply JuicyMachine.resume_step with (tid := i) (Htid := cnti).
          * reflexivity.
          * eapply mem_compatible_forget. eauto.
          * unfold SEM.Sem in *.
            eapply JuicyMachine.ResumeThread with (c := ci) (c' := ci');
              try rewrite SEM.CLN_msem in *;
              simpl.
            -- subst.
               unfold SEM.Sem in *.
               rewrite SEM.CLN_msem in *; simpl.
               reflexivity.
            -- subst.
               unfold SEM.Sem in *.
               rewrite SEM.CLN_msem in *; simpl.
               destruct lid; reflexivity.
            -- rewrite Eci.
               subst ci.
               f_equal.
               specialize (wellformed i cnti).
               rewrite Eci in wellformed.
               simpl in wellformed.
               tauto.
            -- constructor.
            -- reflexivity.
    }
    (* end of Kresume *)
    
    (* thread[i] is in Kinit *)
    {
      eexists(* ; split *).
      - constructor.
        apply JuicyMachine.start_step with (tid := i) (Htid := cnti).
        + reflexivity.
        + eapply mem_compatible_forget. eauto.
        + eapply JuicyMachine.StartThread.
          * apply Eci.
          * simpl.
            (* WE SAID THAT THIS SHOULD NOT BE IN THE MACHINE? *) 
            (* Maybe this is impossible and I have to do all the spawn
               work by myself. *)
           admit.
          * constructor.
          * reflexivity.
    }
    (* end of Kinit *)
  Admitted.
  
End Progress.
