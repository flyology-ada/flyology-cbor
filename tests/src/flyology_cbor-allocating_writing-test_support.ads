package Flyology_CBOR.Allocating_Writing.Test_Support is
   procedure Fail_Allocation_After
     (Self               : in out Writer;
      Successful_Appends : Natural);

   function Retained_Length (Self : Writer) return Natural;

   procedure Set_Output_Copy_Failure
     (Self    : in out Writer;
      Enabled : Boolean);
end Flyology_CBOR.Allocating_Writing.Test_Support;
