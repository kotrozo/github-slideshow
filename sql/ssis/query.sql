/*==============================================================================
  SCMG Coding Worklists - report query
  Goes into the cloned SSIS package (the OLE DB source / Execute SQL task that
  EnsembleVisitOwner already uses).

  If the existing package's SELECT is already identical, the ONLY edit needed
  is the WHERE clause:

      WHERE pv.VisitOwnerMId IN ('153669', '153695', '153696')

  Two corrections against the query as originally supplied:
    - "order by pv.visit desc and and" -> "ORDER BY pv.Visit DESC"
      (the trailing "and and" was a typo and will not parse)
    - column aliases use [brackets] rather than "double quotes", which depend
      on QUOTED_IDENTIFIER being ON
==============================================================================*/

SELECT  pv.TicketNumber,
        pv.Visit,
        ml2.Description  AS [Visit Owner],
        pv.Entered,
        pp.PatientId,
        pp.Last,
        pp.First,
        df.ListName      AS [Doctor],
        df2.ListName     AS [Facility],
        df3.ListName     AS [Company],
        pv.CurrentCarrier,
        pv.[CurrentPICarrierId],
        ml.Description   AS [Bill Status],
        pv.Description,
        LEFT(CAST(pv.ApprovalResults AS nvarchar(max)), 255) AS ApprovalResults,
        pv.Created,
        pv.CreatedBy,
        pv.LastModified,
        pv.LastModifiedBy
FROM    PatientVisit    pv
JOIN    PatientProfile  pp  ON pp.PatientProfileId  = pv.PatientProfileId
JOIN    DoctorFacility  df  ON df.DoctorFacilityId  = pv.DoctorId
JOIN    DoctorFacility  df2 ON df2.DoctorFacilityId = pv.FacilityId
JOIN    DoctorFacility  df3 ON df3.DoctorFacilityId = pv.CompanyId
JOIN    MedLists        ml  ON ml.Code        = pv.BillStatus    AND ml.TableName  = 'BillStatus'
JOIN    MedLists        ml2 ON ml2.MedListsId = pv.VisitOwnerMId AND ml2.TableName = 'VisitOwner'
WHERE   pv.VisitOwnerMId IN ('153669', '153695', '153696')
ORDER BY pv.Visit DESC;
