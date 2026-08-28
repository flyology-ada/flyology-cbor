package body Flyology_CBOR.Allocating_Writing.Test_Support is

   procedure Fail_Allocation_After
     (Self               : in out Writer;
      Successful_Appends : Natural)
   is
   begin
      Self.Target.Allocation_Failure_Armed := True;
      Self.Target.Appends_Before_Failure := Successful_Appends;
   end Fail_Allocation_After;

   function Retained_Length (Self : Writer) return Natural is
     (Natural (Self.Target.Data.Length));

   procedure Set_Output_Copy_Failure
     (Self    : in out Writer;
      Enabled : Boolean)
   is
   begin
      Self.Target.Fail_Output_Copy := Enabled;
   end Set_Output_Copy_Failure;

end Flyology_CBOR.Allocating_Writing.Test_Support;
