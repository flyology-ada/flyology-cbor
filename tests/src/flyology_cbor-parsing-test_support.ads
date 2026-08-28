with Interfaces;

package Flyology_CBOR.Parsing.Test_Support is
   function Inspections (Self : Parser) return Interfaces.Unsigned_64;

   procedure Set_Current_Offset
     (Self  : in out Parser;
      Value : Byte_Offset);
end Flyology_CBOR.Parsing.Test_Support;
