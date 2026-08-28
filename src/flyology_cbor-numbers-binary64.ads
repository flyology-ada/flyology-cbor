with Flyology_CBOR.Values;
with Interfaces;

package Flyology_CBOR.Numbers.Binary64
  with Pure
is
   subtype Encoding is Interfaces.Unsigned_64;

   type Conversion_Status is
     (Converted_Finite,
      Converted_Positive_Infinity,
      Converted_Negative_Infinity,
      Converted_Not_A_Number);

   type Conversion_Result is private;
   --  Value is eligible only for Converted_Finite. Nonfinite results expose category only, so no
   --  NaN payload, sign, or signaling-state promise is made.

   procedure Convert
     (Item   : Values.Float_Value;
      Result : out Conversion_Result);

   function Status (Result : Conversion_Result) return Conversion_Status;

   function Value (Result : Conversion_Result) return Encoding
   with Pre => Status (Result) = Converted_Finite;

private
   type Conversion_Result is record
      Status_Value : Conversion_Status := Converted_Not_A_Number;
      Result_Value : Encoding := 0;
   end record;
end Flyology_CBOR.Numbers.Binary64;
