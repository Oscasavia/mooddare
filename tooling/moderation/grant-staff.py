"""Grant one verified existing Google user staff access using the owner's CLI login.
Run only after deploying the server-only moderation collection rules.
Usage: python3 tooling/moderation/grant-staff.py oscasavia@gmail.com
No credentials are printed or written to the repository.
"""
import datetime,json,pathlib,sys,urllib.request
email=sys.argv[1]
access=json.loads((pathlib.Path.home()/'.config/configstore/firebase-tools.json').read_text())['tokens']['access_token']
def request(url,data):
    req=urllib.request.Request(url,data=json.dumps(data).encode(),headers={'Authorization':'Bearer '+access,'Content-Type':'application/json'},method='POST')
    with urllib.request.urlopen(req) as r:return json.load(r)
users=request('https://identitytoolkit.googleapis.com/v1/projects/mooddare/accounts:lookup',{'email':[email]}).get('users',[])
assert len(users)==1,'Expected exactly one existing Firebase account.'
user=users[0]
assert user.get('emailVerified') and any(p['providerId']=='google.com' for p in user.get('providerUserInfo',[])),'A verified Google account is required.'
uid=user['localId']
name='projects/mooddare/databases/(default)/documents/moderationStaff/'+uid
request('https://firestore.googleapis.com/v1/projects/mooddare/databases/(default)/documents:commit',{'writes':[{'update':{'name':name,'fields':{'enabled':{'booleanValue':True},'email':{'stringValue':email},'grantedAt':{'timestampValue':datetime.datetime.now(datetime.timezone.utc).isoformat()}}}}]})
print('Moderation access granted to the verified account:',email)
