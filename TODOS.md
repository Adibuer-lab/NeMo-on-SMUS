1. Change naming convention for hyperpod stack to begin with datazone environment id, change associated permissions variables
2. Review custom resources, make sure they send robust cfnresponse for all scenarios.
3. Review and scope down permissions where possible
3.scope down domain owner for connection creation, maybe to environment level? along with trust policy?
4. see if mlflow server can be linked to smus managed mlflow servers
5. check if can have instance groups handle multiple availability zones and instance types
6. output actual cluster ame