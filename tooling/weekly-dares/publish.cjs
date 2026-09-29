// Dry run by default. Uses the existing Firebase CLI login; never prints tokens.
const {execFileSync} = require('node:child_process');
const path = require('node:path');
const DAY = 86400000;
const prompts = [
  ['A little joy', 'Happy', 'Capture one small thing that made you smile today.'],
  ['A fresh perspective', 'Creative', 'Show an everyday object from an unexpected angle.'],
  ['Your quiet corner', 'Chill', 'Share a little corner that helps you unwind. Keep private details out of frame.'],
  ['Something new', 'Curious', 'Show something interesting you noticed today and tell us what caught your eye.'],
  ['A tiny performance', 'Silly', 'Give an everyday object a dramatic introduction.'],
  ['Your happy move', 'Energized', 'Show your favorite little celebration move, at your own pace.'],
  ['Color of the day', 'Creative', 'Choose a color and capture three things in that color.'],
  ['Small appreciation', 'Happy', 'Share something simple you are grateful for today.'],
  ['A slower moment', 'Chill', 'Capture a peaceful moment you would like to hold onto.'],
  ['Tell its story', 'Curious', 'Show an object you love and share the story behind it.'],
  ['Unexpected talent', 'Silly', 'Show a harmless, wonderfully unimportant talent of yours.'],
  ['A little progress', 'Energized', 'Celebrate one small thing you finished or tried this week.'],
];
function buildSchedule(start = new Date(), weeks = 52) {
  if (!Number.isInteger(weeks) || weeks < 1 || weeks > 104 || !Number.isFinite(start.getTime())) throw new Error('Use a valid start date and 1–104 weeks.');
  const monday = Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate()) - ((start.getUTCDay() + 6) % 7) * DAY;
  const epoch = Date.UTC(2026, 8, 21);
  return Array.from({length: weeks}, (_, index) => {
    const from = monday + index * 7 * DAY;
    const slot = ((Math.floor((from - epoch) / (7 * DAY)) % prompts.length) + prompts.length) % prompts.length;
    const [title, moodName, dareText] = prompts[slot];
    return {id: new Date(from).toISOString().slice(0,10), title, moodId: moodName.toLowerCase(), moodName, dareText,
      startsAt: new Date(from).toISOString(), endsAt: new Date(from + 7 * DAY).toISOString()};
  });
}
function fieldsFor(entry) {
  return Object.fromEntries(Object.entries(entry).filter(([key]) => key !== 'id').map(([key,value]) =>
    [key, key.endsWith('At') ? {timestampValue:value} : {stringValue:value}]));
}
async function main() {
  const args = process.argv.slice(2);
  const option = (name, fallback) => args.includes(name) ? args[args.indexOf(name)+1] : fallback;
  const schedule = buildSchedule(new Date(option('--start', new Date().toISOString())), Number(option('--weeks',52)));
  const project = option('--project', 'mooddare');
  if (!/^[a-z0-9-]+$/.test(project)) throw new Error('Invalid project ID.');
  if (!args.includes('--apply')) { console.log(JSON.stringify({project, dryRun:true, schedule},null,2)); return; }
  const root = path.join(execFileSync('npm',['root','-g'],{encoding:'utf8'}).trim(),'firebase-tools','lib');
  const {requireAuth} = require(path.join(root,'requireAuth'));
  const {getGlobalDefaultAccount} = require(path.join(root,'auth'));
  const {Client} = require(path.join(root,'apiv2'));
  await requireAuth({project,nonInteractive:true,...getGlobalDefaultAccount()});
  const api = new Client({urlPrefix:'https://firestore.googleapis.com',apiVersion:'v1'});
  const base = `projects/${project}/databases/(default)/documents`;
  // Resolve existing mood IDs so post filtering uses the same catalogue identity.
  const moods = (await api.get(`${base}/dares`,{queryParams:{pageSize:100}})).body.documents || [];
  for (const entry of schedule) {
    const mood = moods.find(doc => doc.fields?.name?.stringValue?.toLowerCase() === entry.moodName.toLowerCase());
    if (mood) { entry.moodId = mood.name.split('/').pop(); entry.moodName = mood.fields.name.stringValue; }
  }
  const writes = [];
  for (const entry of schedule) {
    const name = `${base}/weeklyDares/${entry.id}`;
    const response = await api.get(name,{resolveOnHTTPError:true});
    if (response.status === 200) continue;
    if (response.status !== 404) throw new Error(`Unable to check week ${entry.id} (HTTP ${response.status}).`);
    writes.push({update:{name,fields:fieldsFor(entry)},currentDocument:{exists:false}});
  }
  if (writes.length) await api.post(`${base}:commit`,{writes});
  console.log(JSON.stringify({project,created:writes.length,unchanged:schedule.length-writes.length,
    firstWeek:schedule[0].id,scheduledUntil:schedule.at(-1).endsAt}));
}
module.exports = {buildSchedule, fieldsFor};
if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 1; });
