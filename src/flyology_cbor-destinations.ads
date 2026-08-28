package Flyology_CBOR.Destinations
  with Pure
is
   --  Begin_Succeeded starts one unpublished transaction. Begin_Failed starts none.
   type Begin_Status is (Begin_Succeeded, Begin_Failed);

   --  Write_Succeeded accepts all supplied data. Write_Exhausted accepts exactly the
   --  reported longest prefix. Write_Failed accepts none. Every accepted byte remains unpublished.
   type Write_Status is (Write_Succeeded, Write_Exhausted, Write_Failed);

   --  Commit_Succeeded publishes exactly once. Commit_Failed publishes nothing and leaves
   --  the transaction abortable.
   type Commit_Status is (Commit_Succeeded, Commit_Failed);

   --  Both outcomes end the unpublished transaction without publication. Abort_Failed reports
   --  cleanup trouble but does not retain transaction ownership.
   type Abort_Status is (Abort_Succeeded, Abort_Failed);
end Flyology_CBOR.Destinations;
