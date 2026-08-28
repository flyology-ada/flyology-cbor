with Flyology_CBOR.Values;

generic
   type Value_Type is range <>;
package Flyology_CBOR.Numbers.Signed_Integers is
   type Conversion_Status is (Converted, Below_Range, Above_Range);

   type Conversion_Result is private;

   procedure Convert
     (Item   : Values.Integer_Value;
      Result : out Conversion_Result);

   function Status (Result : Conversion_Result) return Conversion_Status;

   function Value (Result : Conversion_Result) return Value_Type
   with Pre => Status (Result) = Converted;

private
   type Conversion_Result is record
      Status_Value : Conversion_Status := Below_Range;
      Result_Value : Value_Type := Value_Type'First;
   end record;
end Flyology_CBOR.Numbers.Signed_Integers;
