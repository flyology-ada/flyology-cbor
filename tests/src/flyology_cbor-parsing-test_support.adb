package body Flyology_CBOR.Parsing.Test_Support is

   function Inspections (Self : Parser) return Interfaces.Unsigned_64 is
     (Self.Inspection_Count);

   procedure Set_Current_Offset
     (Self  : in out Parser;
      Value : Byte_Offset)
   is
   begin
      Self.Current_Offset := Value;
   end Set_Current_Offset;

end Flyology_CBOR.Parsing.Test_Support;
