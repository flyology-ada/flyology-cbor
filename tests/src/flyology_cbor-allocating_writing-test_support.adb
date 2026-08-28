package body Flyology_CBOR.Allocating_Writing.Test_Support is

   procedure Fail_Next_Allocation (Self : in out Writer) is
   begin
      Self.Target.Fail_Next_Allocation := True;
   end Fail_Next_Allocation;

end Flyology_CBOR.Allocating_Writing.Test_Support;
