Require Import compcert.common.Memory.


Require Import veric.compcert_rmaps.
Require Import veric.juicy_mem.
Require Import veric.res_predicates.

(*IM using proof irrelevance!*)
Require Import ProofIrrelevance.

(* The concurrent machinery*)
Require Import concurrency.scheduler.
Require Import concurrency.concurrent_machine.
Require Import concurrency.juicy_machine. Import Concur.
Require Import concurrency.dry_machine. Import Concur.
(*Require Import concurrency.dry_machine_lemmas. *)
Require Import concurrency.lksize.
Require Import concurrency.permissions.

(*Semantics*)
Require Import veric.Clight_new.
Require Import veric.Clightnew_coop.
Require Import sepcomp.event_semantics.
Require Import concurrency.ClightSemantincsForMachines.

Module THE_JUICY_MACHINE.
  Module SCH:= ListScheduler NatTID.            
  Module SEM:= ClightSEM.
  Import SCH SEM.

  Module JSEM := JuicyMachineShell SEM. (* JuicyMachineShell : Semantics -> ConcurrentSemanticsSig *)
  Module JuicyMachine := CoarseMachine SCH JSEM. (* CoarseMachine : Schedule -> ConcurrentSemanticsSig -> ConcurrentSemantics *)
  Notation JMachineSem:= JuicyMachine.MachineSemantics.
  Notation jstate:= JuicyMachine.SIG.ThreadPool.t.
  Notation jmachine_state:= JuicyMachine.MachState.
  Module JTP:=JuicyMachine.SIG.ThreadPool.
  Import JSEM.JuicyMachineLemmas.

End THE_JUICY_MACHINE.