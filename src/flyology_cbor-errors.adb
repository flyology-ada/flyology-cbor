package body Flyology_CBOR.Errors is

   procedure Clear (Item : out Diagnostic) is
   begin
      Item :=
        (Code                 => No_Error,
         Coordinate           => No_Coordinate,
         Offset               => 0,
         Has_Construct_Offset => False,
         Construct_Offset     => 0,
         Secondary            => No_Error,
         Secondary_Coordinate => No_Coordinate,
         Secondary_Offset     => 0);
   end Clear;

end Flyology_CBOR.Errors;
