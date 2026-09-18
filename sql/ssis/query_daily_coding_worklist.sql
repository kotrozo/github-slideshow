/*==============================================================================
  SCMG Coding Worklists - DAILY report query

  Same WHERE clause as the weekly report, but a different column set:
    - no CurrentCarrier, no CurrentPICarrierId
    - ApprovalResults in full (not truncated to 255)
    - ORDER BY pv.Visit ASCENDING

  Corrections against the query as supplied:
    - aliases use [brackets] rather than "double quotes", which depend on
      QUOTED_IDENTIFIER being ON
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
        ml.Description   AS [Bill Status],
        pv.Description,
        CAST(pv.ApprovalResults AS nvarchar(max)) AS ApprovalResults,
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
ORDER BY pv.Visit;
