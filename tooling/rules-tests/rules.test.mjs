import { readFile } from 'node:fs/promises';
import { before, after, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp, Timestamp, collection, collectionGroup, query, where, orderBy, startAt, endAt, limit, getDocs, getCountFromServer } from 'firebase/firestore';
import { ref, uploadBytes, deleteObject, listAll } from 'firebase/storage';
let env;
before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-mooddare',
    firestore: {rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8')},
    storage: {rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8')},
  });
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); await env.clearStorage(); });
const db = uid => env.authenticatedContext(uid).firestore();
const post = (uid = 'alice') => ({dareText: 'Try a new perspective', mediaType: 'image', authorId: uid,
  mediaPath: `posts/${uid}/one.jpg`, mediaUrl: 'https://firebasestorage.googleapis.com/v0/b/demo-mooddare/o/posts%2Falice%2Fone.jpg?alt=media',
  createdAt: serverTimestamp(), expiresAt: Timestamp.fromMillis(Date.now() + 86400000), likedBy: []});
test('anonymous requests cannot read profiles or write posts', async () => {
  const guest = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(guest, 'users/alice')));
  await assertFails(setDoc(doc(guest, 'posts/one'), post()));
});
test('profile creation excludes private email data and cannot impersonate another user', async () => {
  await assertFails(setDoc(doc(db('bob'), 'users/alice'), {id: 'alice', createdAt: serverTimestamp()}));
  await assertFails(setDoc(doc(db('alice'), 'users/alice'), {id: 'alice', email: 'private@example.com', createdAt: serverTimestamp()}));
  await assertSucceeds(setDoc(doc(db('alice'), 'users/alice'), {id: 'alice', createdAt: serverTimestamp()}));
});
test('username and profile must be claimed together, and claims cannot be stolen', async () => {
  const alice = db('alice');
  await assertFails(setDoc(doc(alice, 'usernames/alice'), {uid: 'alice'}));
  const batch = writeBatch(alice);
  batch.set(doc(alice, 'users/alice'), {id: 'alice', username: 'Alice', username_lower: 'alice', createdAt: serverTimestamp()});
  batch.set(doc(alice, 'usernames/alice'), {uid: 'alice'});
  await assertSucceeds(batch.commit());
  await assertFails(setDoc(doc(db('bob'), 'usernames/alice'), {uid: 'bob'}));
});
test('post author, size metadata and timestamps are validated', async () => {
  await assertFails(setDoc(doc(db('bob'), 'posts/one'), post()));
  await assertFails(setDoc(doc(db('alice'), 'posts/one'), {...post(), likedBy: ['bob']}));
  await assertFails(setDoc(doc(db('alice'), 'posts/one'), {...post(), mediaPath: 'posts/bob/one.jpg'}));
  await assertSucceeds(setDoc(doc(db('alice'), 'posts/one'), post()));
  await assertFails(updateDoc(doc(db('alice'), 'posts/one'), {dareText: 'Edited via unauthorized client'}));
});
test('likes can only add or remove the caller, without duplicate counts', async () => {
  await setDoc(doc(db('alice'), 'posts/one'), post());
  const bob = doc(db('bob'), 'posts/one');
  await assertSucceeds(updateDoc(bob, {likedBy: ['bob']}));
  await assertFails(updateDoc(bob, {likedBy: ['bob', 'alice']}));
  await assertFails(updateDoc(bob, {likedBy: ['bob', 'bob']}));
  await assertSucceeds(updateDoc(doc(db('alice'), 'posts/one'), {likedBy: ['bob', 'alice']}));
  await assertFails(updateDoc(bob, {likedBy: []}));
  await assertSucceeds(updateDoc(bob, {likedBy: ['alice']}));
});
test('only the author can delete a post; reports are private to their reporter', async () => {
  await setDoc(doc(db('alice'), 'posts/one'), post());
  await assertFails(deleteDoc(doc(db('bob'), 'posts/one')));
  await assertSucceeds(setDoc(doc(db('bob'), 'reports/bob_one'), {postId: 'one', reporterId: 'bob', reason: 'inappropriate', createdAt: serverTimestamp()}));
  await assertFails(getDoc(doc(db('alice'), 'reports/bob_one')));
  await assertSucceeds(deleteDoc(doc(db('alice'), 'posts/one')));
});
test('storage rejects cross-user writes and non-media content', async () => {
  const alice = env.authenticatedContext('alice').storage();
  const bob = env.authenticatedContext('bob').storage();
  await assertFails(uploadBytes(ref(bob, 'posts/alice/one.jpg'), new Uint8Array([1]), {contentType: 'image/jpeg'}));
  await assertFails(uploadBytes(ref(alice, 'posts/alice/code.html'), new Uint8Array([1]), {contentType: 'text/html'}));
  await assertSucceeds(uploadBytes(ref(alice, 'posts/alice/one.jpg'), new Uint8Array([1]), {contentType: 'image/jpeg'}));
  await assertFails(deleteObject(ref(bob, 'posts/alice/one.jpg')));
  await assertSucceeds(listAll(ref(alice, 'posts/alice')));
  await assertSucceeds(deleteObject(ref(alice, 'posts/alice/one.jpg')));
});
test('blocked accounts are private and cannot be written for another user', async () => {
  await assertSucceeds(setDoc(doc(db('alice'), 'users/alice/blocked/bob'), {createdAt: serverTimestamp()}));
  await assertFails(getDoc(doc(db('bob'), 'users/alice/blocked/bob')));
  await assertFails(setDoc(doc(db('bob'), 'users/alice/blocked/charlie'), {createdAt: serverTimestamp()}));
  await assertSucceeds(deleteDoc(doc(db('alice'), 'users/alice/blocked/bob')));
});
test('a username cannot be released while the profile still claims it', async () => {
  const alice = db('alice');
  const batch = writeBatch(alice);
  batch.set(doc(alice, 'users/alice'), {id: 'alice', username: 'Alice', username_lower: 'alice', createdAt: serverTimestamp()});
  batch.set(doc(alice, 'usernames/alice'), {uid: 'alice'});
  await batch.commit();
  await assertFails(deleteDoc(doc(alice, 'usernames/alice')));
  const deletion = writeBatch(alice);
  deletion.delete(doc(alice, 'users/alice'));
  deletion.delete(doc(alice, 'usernames/alice'));
  await assertSucceeds(deletion.commit());
});

const comment = (uid = 'bob', text = 'Love this!') => ({authorId: uid, text, createdAt: serverTimestamp()});
for (const policy of ['firestore.rules', 'firestore.compat.rules']) {
  test(`${policy}: usernames reject punctuation-only, numeric-only and ambiguous underscores while preserving unchanged legacy handles`, async () => {
    await env.cleanup();
    env = await initializeTestEnvironment({projectId: 'demo-mooddare',
      firestore: {rules: await readFile(new URL(`../../${policy}`, import.meta.url), 'utf8')},
      storage: {rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8')},
    });
    const alice = db('alice');
    const save = name => {
      const batch = writeBatch(alice);
      batch.set(doc(alice, 'users/alice'), {id:'alice', username:name, username_lower:name.toLowerCase(), createdAt:serverTimestamp()});
      batch.set(doc(alice, `usernames/${name.toLowerCase()}`), {uid:'alice'});
      return batch.commit();
    };
    for (const name of ['___','123','a__b','_alice','alice_','a.b','a-b','@alice','ab','a'.repeat(21)]) await assertFails(save(name));
    await assertSucceeds(save('Mood_123'));
    await assertFails(updateDoc(doc(db('alice'), 'users/alice'), {username:'___', username_lower:'___'}));
    await env.withSecurityRulesDisabled(async context => {
      await setDoc(doc(context.firestore(), 'users/legacy'), {id:'legacy', username:'___', username_lower:'___', createdAt:Timestamp.now()});
      await setDoc(doc(context.firestore(), 'usernames/___'), {uid:'legacy'});
    });
    await assertSucceeds(updateDoc(doc(db('legacy'), 'users/legacy'), {bio:'Still here'}));
  });

  test(`${policy}: username discovery allows signed-in prefix queries but denies signed-out requests`, async () => {
    await env.cleanup();
    env = await initializeTestEnvironment({projectId: 'demo-mooddare',
      firestore: {rules: await readFile(new URL(`../../${policy}`, import.meta.url), 'utf8')},
      storage: {rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8')},
    });
    await env.withSecurityRulesDisabled(async context => {
      await setDoc(doc(context.firestore(), 'users/alice'), {id:'alice', username:'Alice', username_lower:'alice'});
    });
    const search = client => query(collection(client, 'users'), orderBy('username_lower'), startAt('al'), endAt('al\uf8ff'), limit(21));
    const result = await assertSucceeds(getDocs(search(db('bob'))));
    if (result.docs.length !== 1) throw new Error('Expected matching public profile');
    await assertFails(getDocs(search(env.unauthenticatedContext().firestore())));
  });

  test(`${policy}: comments enforce identity, content, parent and deletion permissions`, async () => {
    await env.cleanup();
    env = await initializeTestEnvironment({projectId: 'demo-mooddare',
      firestore: {rules: await readFile(new URL(`../../${policy}`, import.meta.url), 'utf8')},
      storage: {rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8')},
    });
    await setDoc(doc(db('alice'), 'posts/one'), post());
    const bob = db('bob');
    await assertFails(setDoc(doc(env.unauthenticatedContext().firestore(), 'posts/one/comments/c'), comment()));
    await assertFails(setDoc(doc(bob, 'posts/missing/comments/c'), comment()));
    await assertFails(setDoc(doc(bob, 'posts/one/comments/c'), comment('alice')));
    for (const text of ['', '   ', '\n \t', 'x'.repeat(501)]) {
      await assertFails(setDoc(doc(bob, 'posts/one/comments/c'), comment('bob', text)));
    }
    await assertFails(setDoc(doc(bob, 'posts/one/comments/c'), {...comment(), createdAt: Timestamp.fromMillis(1)}));
    await assertFails(setDoc(doc(bob, 'posts/one/comments/c'), {...comment(), admin: true}));
    await assertSucceeds(setDoc(doc(bob, 'posts/one/comments/c'), comment('bob', 'Nice!\nA second line 😊')));
    await assertSucceeds(getDocs(query(collection(db('charlie'), 'posts/one/comments'), orderBy('createdAt', 'desc'))));
    await assertFails(getDocs(collection(env.unauthenticatedContext().firestore(), 'posts/one/comments')));
    await assertFails(updateDoc(doc(bob, 'posts/one/comments/c'), {text: 'Changed'}));
    await assertFails(deleteDoc(doc(env.unauthenticatedContext().firestore(), 'posts/one/comments/c')));
    await assertFails(deleteDoc(doc(db('charlie'), 'posts/one/comments/c')));
    await assertSucceeds(deleteDoc(doc(db('alice'), 'posts/one/comments/c')));
    if ((await getDoc(doc(bob, 'posts/one/comments/c'))).exists()) throw new Error('Deleted comment remains');
    await setDoc(doc(bob, 'posts/one/comments/c'), comment());
    await assertSucceeds(deleteDoc(doc(bob, 'posts/one/comments/c')));
    await assertFails(deleteDoc(doc(bob, 'posts/one')));
    await assertFails(updateDoc(doc(bob, 'posts/one'), {authorId: 'bob'}));
  });
  test(`${policy}: comment edits preserve identity, creation time and likes`, async () => {
    await env.cleanup();
    env = await initializeTestEnvironment({projectId: 'demo-mooddare',
      firestore: {rules: await readFile(new URL(`../../${policy}`, import.meta.url), 'utf8')},
      storage: {rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8')},
    });
    await setDoc(doc(db('alice'), 'posts/one'), post());
    const bob = doc(db('bob'), 'posts/one/comments/c');
    await setDoc(bob, comment());
    await assertSucceeds(updateDoc(bob, {text: 'Corrected text', editedAt: serverTimestamp()}));
    await assertFails(updateDoc(doc(db('alice'), 'posts/one/comments/c'), {text: 'Post owner edit', editedAt: serverTimestamp()}));
    await assertFails(updateDoc(doc(db('charlie'), 'posts/one/comments/c'), {text: 'Someone else', editedAt: serverTimestamp()}));
    for (const text of ['', '   ', 'x'.repeat(501)]) {
      await assertFails(updateDoc(bob, {text, editedAt: serverTimestamp()}));
    }
    await assertFails(updateDoc(bob, {text: 'No timestamp'}));
    await assertFails(updateDoc(bob, {text: 'Forged date', editedAt: Timestamp.fromMillis(1)}));
    await assertFails(updateDoc(bob, {authorId: 'alice', editedAt: serverTimestamp()}));
    await assertFails(updateDoc(bob, {text: 'Creation changed', createdAt: serverTimestamp(), editedAt: serverTimestamp()}));
    await assertFails(updateDoc(bob, {text: 'Pre-liked', likedBy: ['bob'], editedAt: serverTimestamp()}));
    await assertSucceeds(getCountFromServer(collection(db('alice'), 'posts/one/comments')));
    {
      const count = await getCountFromServer(collection(db('bob'), 'posts/one/comments'));
      if (count.data().count !== 1) throw new Error('Expected every comment to be counted');
    }
  });
  test(`${policy}: comment likes are unique, caller-only and work on older comments`, async () => {
    await env.cleanup();
    env = await initializeTestEnvironment({projectId: 'demo-mooddare',
      firestore: {rules: await readFile(new URL(`../../${policy}`, import.meta.url), 'utf8')},
      storage: {rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8')},
    });
    await setDoc(doc(db('alice'), 'posts/one'), post());
    const bob = doc(db('bob'), 'posts/one/comments/c');
    await assertFails(setDoc(bob, {...comment(), likedBy: ['bob']}));
    await setDoc(bob, comment()); // Existing comments have no likedBy field.
    const alice = doc(db('alice'), 'posts/one/comments/c');
    await assertSucceeds(updateDoc(alice, {likedBy: ['alice']}));
    await assertFails(updateDoc(bob, {likedBy: ['alice', 'charlie']}));
    await assertFails(updateDoc(bob, {likedBy: ['alice', 'bob', 'bob']}));
    await assertSucceeds(updateDoc(bob, {likedBy: ['alice', 'bob']}));
    await assertFails(updateDoc(alice, {likedBy: []}));
    await assertSucceeds(updateDoc(alice, {likedBy: ['bob']}));
    await assertSucceeds(updateDoc(bob, {text: 'Edited after likes', editedAt: serverTimestamp()}));
    const data = (await getDoc(bob)).data();
    if (data.likedBy.join(',') !== 'bob') throw new Error('Editing must retain likes');
    await assertFails(updateDoc(doc(env.unauthenticatedContext().firestore(), 'posts/one/comments/c'), {likedBy: []}));
    await deleteDoc(doc(db('alice'), 'posts/one'));
    await assertFails(updateDoc(bob, {likedBy: []}));
    await assertFails(updateDoc(bob, {text: 'Orphan edit', editedAt: serverTimestamp()}));
  });
  test(`${policy}: mood metadata stays paired and immutable; legacy posts still work`, async () => {
    await env.cleanup();
    env = await initializeTestEnvironment({projectId: 'demo-mooddare',
      firestore: {rules: await readFile(new URL(`../../${policy}`, import.meta.url), 'utf8')},
      storage: {rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8')},
    });
    const ref = doc(db('alice'), 'posts/one');
    await assertFails(setDoc(ref, {...post(), moodId: 'happy'}));
    await assertFails(setDoc(ref, {...post(), moodId: 7, moodName: 'Happy'}));
    await assertFails(setDoc(ref, {...post(), moodId: 'happy', moodName: ''}));
    await assertSucceeds(setDoc(ref, {...post(), moodId: 'happy', moodName: 'Happy'}));
    await assertFails(updateDoc(ref, {moodId: 'calm'}));
    await deleteDoc(ref);
    await assertSucceeds(setDoc(ref, post()));
  });
  test(`${policy}: account cleanup can query only its own comments including orphans`, async () => {
    await env.cleanup();
    env = await initializeTestEnvironment({projectId: 'demo-mooddare',
      firestore: {rules: await readFile(new URL(`../../${policy}`, import.meta.url), 'utf8')},
      storage: {rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8')},
    });
    await setDoc(doc(db('alice'), 'posts/one'), post());
    await setDoc(doc(db('bob'), 'posts/one/comments/c'), comment());
    await deleteDoc(doc(db('alice'), 'posts/one'));
    await assertFails(getDocs(collection(db('charlie'), 'posts/one/comments')));
    const own = query(collectionGroup(db('bob'), 'comments'), where('authorId', '==', 'bob'));
    await assertSucceeds(getDocs(own));
    await assertFails(getDocs(query(collectionGroup(db('charlie'), 'comments'), where('authorId', '==', 'bob'))));
    await assertSucceeds(deleteDoc(doc(db('bob'), 'posts/one/comments/c')));
  });
}

for (const policy of ['firestore.rules', 'firestore.compat.rules']) {
  async function loadSocialPolicy() {
    await env.cleanup();
    env = await initializeTestEnvironment({projectId: 'demo-mooddare',
      firestore: {rules: await readFile(new URL(`../../${policy}`, import.meta.url), 'utf8')},
      storage: {rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8')},
    });
  }
  test(`${policy}: user reports validate targets and reasons, stay private, and cannot be forged or retargeted`, async () => {
    await loadSocialPolicy();
    for (const uid of ['alice','bob','charlie']) await setDoc(doc(db(uid), `users/${uid}`), {id: uid, createdAt: serverTimestamp()});
    const data = {userId: 'bob', reporterId: 'alice', reason: 'harassment', createdAt: serverTimestamp()};
    const path = 'reports/alice_user_bob';
    await assertFails(setDoc(doc(env.unauthenticatedContext().firestore(), path), data));
    await assertFails(setDoc(doc(db('bob'), path), data));
    await assertFails(setDoc(doc(db('alice'), path), {...data, reason: 'invalid'}));
    await assertFails(setDoc(doc(db('alice'), path), {...data, reviewed: true}));
    await assertFails(setDoc(doc(db('alice'), path), {...data, createdAt: Timestamp.fromMillis(1)}));
    await assertFails(setDoc(doc(db('alice'), 'reports/wrong'), data));
    await assertFails(setDoc(doc(db('alice'), 'reports/alice_user_alice'), {...data, userId:'alice'}));
    await assertFails(setDoc(doc(db('alice'), 'reports/alice_user_missing'), {...data, userId:'missing'}));
    await assertSucceeds(setDoc(doc(db('alice'), path), data));
    await assertSucceeds(getDoc(doc(db('alice'), path)));
    for (const reason of ['spam','hate','sexualContent','violence','impersonation','other']) {
      await assertSucceeds(setDoc(doc(db('alice'), path), {...data, reason}));
    }
    await assertFails(getDoc(doc(db('bob'), path)));
    await assertFails(getDoc(doc(db('charlie'), path)));
    await assertFails(updateDoc(doc(db('charlie'), path), {reason:'spam',createdAt:serverTimestamp()}));
    await assertFails(updateDoc(doc(db('alice'), path), {userId:'charlie',createdAt:serverTimestamp()}));
    await assertFails(setDoc(doc(db('alice'), path), {postId:'user_bob',reporterId:'alice',reason:'inappropriate',createdAt:serverTimestamp()}));
    await assertFails(deleteDoc(doc(db('bob'), path)));
    await assertSucceeds(deleteDoc(doc(db('alice'), path)));
    await assertSucceeds(setDoc(doc(db('alice'), 'reports/alice_one'), {postId:'one',reporterId:'alice',reason:'inappropriate',createdAt:serverTimestamp()}));
  });
  const edge = (client, follower, target, remove = false) => {
    const batch = writeBatch(client);
    for (const path of [`users/${follower}/following/${target}`, `users/${target}/followers/${follower}`]) {
      if (remove) batch.delete(doc(client, path));
      else batch.set(doc(client, path), {createdAt: serverTimestamp()});
    }
    return batch;
  };
  test(`${policy}: following requires paired edges, own identity, existing profiles and no self-follow`, async () => {
    await loadSocialPolicy();
    for (const uid of ['alice', 'bob']) await setDoc(doc(db(uid), `users/${uid}`), {id: uid, createdAt: serverTimestamp()});
    await assertFails(setDoc(doc(db('alice'), 'users/alice/following/bob'), {createdAt: serverTimestamp()}));
    await assertFails(edge(db('bob'), 'alice', 'bob').commit());
    await assertFails(edge(db('alice'), 'alice', 'alice').commit());
    await assertFails(edge(db('alice'), 'alice', 'missing').commit());
    await assertSucceeds(edge(db('alice'), 'alice', 'bob').commit());
    await assertSucceeds(getCountFromServer(collection(db('bob'), 'users/bob/followers')));
    await assertFails(getDocs(collection(env.unauthenticatedContext().firestore(), 'users/bob/followers')));
    await assertFails(updateDoc(doc(db('alice'), 'users/alice/following/bob'), {createdAt: serverTimestamp()}));
    await assertFails(deleteDoc(doc(db('alice'), 'users/alice/following/bob')));
    await assertFails(edge(db('charlie'), 'alice', 'bob', true).commit());
    await assertSucceeds(edge(db('alice'), 'alice', 'bob', true).commit());
    await assertSucceeds(edge(db('alice'), 'alice', 'bob').commit());
    await assertSucceeds(edge(db('bob'), 'alice', 'bob', true).commit());
  });
  test(`${policy}: blocking removes both directions atomically and blocks new follows from either side`, async () => {
    await loadSocialPolicy();
    for (const uid of ['alice', 'bob']) await setDoc(doc(db(uid), `users/${uid}`), {id: uid, createdAt: serverTimestamp()});
    await edge(db('alice'), 'alice', 'bob').commit();
    await edge(db('bob'), 'bob', 'alice').commit();
    const client = db('alice'), batch = writeBatch(client);
    batch.set(doc(client, 'users/alice/blocked/bob'), {createdAt: serverTimestamp()});
    for (const path of ['users/alice/following/bob', 'users/bob/followers/alice', 'users/bob/following/alice', 'users/alice/followers/bob']) batch.delete(doc(client, path));
    await assertSucceeds(batch.commit());
    await assertFails(getDoc(doc(db('bob'), 'users/alice/blocked/bob')));
    await assertFails(edge(db('alice'), 'alice', 'bob').commit());
    await assertFails(edge(db('bob'), 'bob', 'alice').commit());
    await deleteDoc(doc(client, 'users/alice/blocked/bob'));
    await assertSucceeds(edge(db('bob'), 'bob', 'alice').commit());
  });
  test(`${policy}: replies require a live root and cannot be forged, reparented or written to another post`, async () => {
    await loadSocialPolicy();
    await setDoc(doc(db('alice'), 'posts/one'), post());
    await setDoc(doc(db('bob'), 'posts/one/comments/root'), comment());
    const value = {...comment('charlie'), parentId: 'root', rootAuthorId: 'bob'};
    const reply = doc(db('charlie'), 'posts/one/replies/reply');
    await assertFails(setDoc(reply, {...value, authorId: 'bob'}));
    await assertFails(setDoc(reply, {...value, rootAuthorId: 'charlie'}));
    await assertFails(setDoc(reply, {...value, parentId: 'missing'}));
    await assertFails(setDoc(reply, {...value, likedBy: ['alice']}));
    await assertFails(setDoc(doc(db('charlie'), 'posts/missing/replies/reply'), value));
    for (const text of ['', '   ', 'x'.repeat(501)]) await assertFails(setDoc(reply, {...value, text}));
    await assertSucceeds(setDoc(reply, value));
    await assertSucceeds(getDocs(query(collection(db('alice'), 'posts/one/replies'), where('parentId', '==', 'root'), orderBy('createdAt'))));
    await assertSucceeds(getCountFromServer(collection(db('alice'), 'posts/one/replies')));
    await assertFails(updateDoc(reply, {parentId: 'other', editedAt: serverTimestamp()}));
    await assertFails(updateDoc(reply, {rootAuthorId: 'charlie'}));
    await assertFails(updateDoc(doc(db('bob'), 'posts/one/replies/reply'), {text: 'Changed', editedAt: serverTimestamp()}));
    await assertSucceeds(updateDoc(reply, {text: 'Edited reply', editedAt: serverTimestamp()}));
    await assertSucceeds(updateDoc(doc(db('bob'), 'posts/one/replies/reply'), {likedBy: ['bob']}));
    await assertFails(updateDoc(reply, {likedBy: []}));
    await assertFails(updateDoc(reply, {likedBy: ['bob', 'charlie', 'charlie']}));
    await assertSucceeds(updateDoc(reply, {likedBy: ['bob', 'charlie']}));
    await assertFails(deleteDoc(doc(db('dana'), 'posts/one/replies/reply')));
    await assertSucceeds(deleteDoc(doc(db('bob'), 'posts/one/replies/reply')));
    await assertSucceeds(setDoc(reply, value));
    await assertSucceeds(deleteDoc(doc(db('alice'), 'posts/one/replies/reply')));
    await assertSucceeds(setDoc(reply, value));
    await assertSucceeds(deleteDoc(reply));
    await assertFails(updateDoc(doc(db('charlie'), 'posts/one/comments/root'), {deleting: true}));
    await assertSucceeds(updateDoc(doc(db('bob'), 'posts/one/comments/root'), {deleting: true}));
    await assertFails(setDoc(reply, value));
    await assertFails(updateDoc(doc(db('bob'), 'posts/one/comments/root'), {deleting: false}));
  });
  test(`${policy}: reply targets are validated in the same thread and cannot be changed`, async () => {
    await loadSocialPolicy();
    await setDoc(doc(db('alice'), 'posts/one'), post());
    await setDoc(doc(db('bob'), 'posts/one/comments/root'), comment());
    await setDoc(doc(db('bob'), 'posts/one/comments/other'), comment());
    const base = {...comment('charlie'), parentId: 'root', rootAuthorId: 'bob'};
    await assertSucceeds(setDoc(doc(db('charlie'), 'posts/one/replies/first'), {...base, replyToAuthorId: 'bob'}));
    await setDoc(doc(db('charlie'), 'posts/one/replies/elsewhere'), {...base, parentId: 'other'});
    const target = doc(db('dana'), 'posts/one/replies/answer');
    const answer = {...base, authorId: 'dana', replyToId: 'first', replyToAuthorId: 'charlie'};
    await assertFails(setDoc(target, {...answer, replyToAuthorId: 'bob'}));
    await assertFails(setDoc(target, {...answer, replyToId: 'elsewhere'}));
    await assertFails(setDoc(target, {...answer, replyToId: 'missing'}));
    await assertFails(setDoc(target, {...answer, replyToId: 123}));
    await assertFails(setDoc(target, {...answer, replyToId: ''}));
    const missingAuthor = {...answer}; delete missingAuthor.replyToAuthorId;
    await assertFails(setDoc(target, missingAuthor));
    const forgedRoot = {...answer}; delete forgedRoot.replyToId;
    await assertFails(setDoc(target, forgedRoot));
    await assertSucceeds(setDoc(target, answer));
    await assertFails(updateDoc(target, {replyToId: 'elsewhere'}));
    await assertFails(updateDoc(target, {replyToAuthorId: 'bob', text: 'Retarget', editedAt: serverTimestamp()}));
    await assertSucceeds(updateDoc(target, {text: 'Still to Charlie', editedAt: serverTimestamp()}));
    // A mention does not grant its recipient moderation over someone else's reply.
    await assertFails(deleteDoc(doc(db('charlie'), 'posts/one/replies/answer')));
    await assertSucceeds(deleteDoc(doc(db('charlie'), 'posts/one/replies/first')));
    await assertSucceeds(updateDoc(target, {text: 'Target was deleted', editedAt: serverTimestamp()}));
    await assertSucceeds(updateDoc(doc(db('bob'), 'posts/one/replies/answer'), {likedBy: ['bob']}));
    await assertFails(setDoc(doc(db('dana'), 'posts/one/replies/new'), answer));
    await assertSucceeds(deleteDoc(doc(db('bob'), 'posts/one/replies/answer')));
  });
  test(`${policy}: own reply collection-group cleanup cannot inspect others' replies`, async () => {
    await loadSocialPolicy();
    await setDoc(doc(db('alice'), 'posts/one'), post());
    await setDoc(doc(db('bob'), 'posts/one/comments/root'), comment());
    await setDoc(doc(db('charlie'), 'posts/one/replies/r'), {...comment('charlie'), parentId: 'root', rootAuthorId: 'bob'});
    await deleteDoc(doc(db('alice'), 'posts/one'));
    await assertSucceeds(getDocs(query(collectionGroup(db('charlie'), 'replies'), where('authorId', '==', 'charlie'))));
    await assertFails(getDocs(query(collectionGroup(db('bob'), 'replies'), where('authorId', '==', 'charlie'))));
    await assertSucceeds(deleteDoc(doc(db('charlie'), 'posts/one/replies/r')));
  });
}

test('post deletion rejects new root comments and replies while allowing cleanup', async () => {
  await setDoc(doc(db('alice'), 'posts/one'), post());
  await setDoc(doc(db('bob'), 'posts/one/comments/root'), comment());
  await assertFails(updateDoc(doc(db('bob'), 'posts/one'), {deleting: true}));
  await assertSucceeds(updateDoc(doc(db('alice'), 'posts/one'), {deleting: true}));
  await assertFails(setDoc(doc(db('bob'), 'posts/one/comments/new'), comment()));
  await assertFails(setDoc(doc(db('bob'), 'posts/one/replies/r'), {...comment(), parentId: 'root', rootAuthorId: 'bob'}));
  await assertSucceeds(deleteDoc(doc(db('alice'), 'posts/one/comments/root')));
  await assertSucceeds(deleteDoc(doc(db('alice'), 'posts/one')));
});

test('account relationship cleanup batches respect paired-edge rules without touching another page', async () => {
  await env.withSecurityRulesDisabled(async context => {
    const client = context.firestore(), seed = writeBatch(client);
    for (let i = 0; i < 11; i++) {
      seed.set(doc(client, `users/alice/following/u${i}`), {createdAt: Timestamp.now()});
      seed.set(doc(client, `users/u${i}/followers/alice`), {createdAt: Timestamp.now()});
    }
    await seed.commit();
  });
  const client = db('alice'), batch = writeBatch(client);
  for (let i = 0; i < 10; i++) {
    batch.delete(doc(client, `users/alice/following/u${i}`));
    batch.delete(doc(client, `users/u${i}/followers/alice`));
  }
  await assertSucceeds(batch.commit());
  const remaining = await getDocs(collection(client, 'users/alice/following'));
  if (remaining.size !== 1 || remaining.docs[0].id !== 'u10') throw new Error('Cleanup crossed its page boundary');
  const last = writeBatch(client);
  last.delete(doc(client, 'users/alice/following/u10'));
  last.delete(doc(client, 'users/u10/followers/alice'));
  await assertSucceeds(last.commit());
});

const darePrompt = () => ({dareText: 'Capture something that made you smile.', moodId: 'happy', moodName: 'Happy'});
const invite = (overrides = {}) => ({...darePrompt(), senderId: 'alice', recipientId: 'bob', opened: false, createdAt: serverTimestamp(), ...overrides});
async function seedMutualDareUsers() {
  await env.withSecurityRulesDisabled(async context => {
    const store = context.firestore();
    for (const uid of ['alice', 'bob', 'charlie']) await setDoc(doc(store, `users/${uid}`), {id: uid});
    for (const [a,b] of [['alice','bob'], ['bob','alice']]) {
      await setDoc(doc(store, `users/${a}/following/${b}`), {createdAt: Timestamp.now()});
      await setDoc(doc(store, `users/${b}/followers/${a}`), {createdAt: Timestamp.now()});
    }
  });
}
for (const policy of ['firestore.rules', 'firestore.compat.rules']) {
  async function loadDarePolicy() {
    await env.cleanup();
    env = await initializeTestEnvironment({projectId: 'demo-mooddare',
      firestore: {rules: await readFile(new URL(`../../${policy}`, import.meta.url), 'utf8')},
      storage: {rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8')},
    });
  }
test(`${policy}: saved dares are owner-only prompt snapshots and survive source post removal`, async () => {
  await loadDarePolicy();
  const saved = doc(db('alice'), 'users/alice/savedDares/one');
  await assertSucceeds(setDoc(saved, {...darePrompt(), createdAt: serverTimestamp()}));
  await assertSucceeds(getDocs(query(collection(db('alice'), 'users/alice/savedDares'), orderBy('createdAt', 'desc'), limit(40))));
  await assertFails(getDoc(doc(db('bob'), saved.path)));
  await assertFails(getDocs(collection(db('bob'), 'users/alice/savedDares')));
  await assertFails(setDoc(doc(db('bob'), 'users/alice/savedDares/two'), {...darePrompt(), createdAt: serverTimestamp()}));
  await assertFails(deleteDoc(doc(db('bob'), saved.path)));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), saved.path)));
  await assertSucceeds(getDoc(saved));
  await assertSucceeds(deleteDoc(saved));
});
test(`${policy}: saved dares reject invalid text, partial moods, media and timestamp tampering`, async () => {
  await loadDarePolicy();
  const ref = doc(db('alice'), 'users/alice/savedDares/one');
  for (const value of [
    {...darePrompt(), dareText: ''}, {...darePrompt(), dareText: ' \n '}, {...darePrompt(), dareText: 'x'.repeat(501)},
    {dareText:'A dare', moodId:'happy'}, {...darePrompt(), moodId:'a/b'}, {...darePrompt(), moodName:''},
    {...darePrompt(), mediaUrl:'https://example.com/photo.jpg'}, {...darePrompt(), recipientId:'bob'},
  ]) await assertFails(setDoc(ref, {...value, createdAt:serverTimestamp()}));
  await assertFails(setDoc(ref, {...darePrompt(), createdAt:Timestamp.fromMillis(1)}));
  await assertSucceeds(setDoc(ref, {dareText:'Legacy dare without mood', createdAt:serverTimestamp()}));
  await assertFails(updateDoc(ref, {dareText:'Changed snapshot'}));
});
test(`${policy}: mutual followers can send invitations and only participants can read or delete them`, async () => {
  await loadDarePolicy();
  await seedMutualDareUsers();
  const alice = doc(db('alice'), 'dareInvites/one');
  await assertSucceeds(getDoc(alice)); // Missing deterministic ID can be checked before sending.
  await assertSucceeds(setDoc(alice, invite()));
  await assertSucceeds(getDoc(doc(db('bob'), alice.path)));
  await assertFails(getDoc(doc(db('charlie'), alice.path)));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), alice.path)));
  await assertFails(deleteDoc(doc(db('charlie'), alice.path)));
  await assertSucceeds(deleteDoc(doc(db('bob'), alice.path)));
});
test(`${policy}: invitation inbox, unread and account cleanup queries are scoped to their participant`, async () => {
  await loadDarePolicy();
  await seedMutualDareUsers();
  await setDoc(doc(db('alice'), 'dareInvites/one'), invite());
  await assertSucceeds(getDocs(query(collection(db('bob'), 'dareInvites'), where('recipientId','==','bob'), orderBy('createdAt','desc'), limit(40))));
  await assertSucceeds(getDocs(query(collection(db('bob'), 'dareInvites'), where('recipientId','==','bob'), where('opened','==',false), limit(1))));
  await assertSucceeds(getDocs(query(collection(db('alice'), 'dareInvites'), where('senderId','==','alice'), limit(100))));
  await assertFails(getDocs(collection(db('alice'), 'dareInvites')));
  await assertFails(getDocs(query(collection(db('charlie'), 'dareInvites'), where('recipientId','==','bob'))));
});
test(`${policy}: invites reject one-way follows, self-send, impersonation and missing users`, async () => {
  await loadDarePolicy();
  await seedMutualDareUsers();
  const ref = doc(db('alice'), 'dareInvites/one');
  for (const value of [{recipientId:'alice'}, {senderId:'bob', recipientId:'alice'}, {recipientId:'charlie'}, {recipientId:'missing'}]) {
    await assertFails(setDoc(ref, invite(value)));
  }
  await env.withSecurityRulesDisabled(context => deleteDoc(doc(context.firestore(), 'users/bob/following/alice')));
  await assertFails(setDoc(ref, invite()));
});
test(`${policy}: either block direction denies invitations even with stale follow records`, async () => {
  await loadDarePolicy();
  await seedMutualDareUsers();
  for (const [a,b] of [['alice','bob'], ['bob','alice']]) {
    await setDoc(doc(db(a), `users/${a}/blocked/${b}`), {createdAt:serverTimestamp()});
    await assertFails(setDoc(doc(db('alice'), 'dareInvites/one'), invite()));
    await deleteDoc(doc(db(a), `users/${a}/blocked/${b}`));
  }
  const client = db('alice'), batch = writeBatch(client);
  batch.set(doc(client, 'users/alice/blocked/bob'), {createdAt:serverTimestamp()});
  batch.set(doc(client, 'dareInvites/one'), invite());
  await assertFails(batch.commit());
});
test(`${policy}: only the recipient can acknowledge a dare; neither person can rewrite or resend the snapshot`, async () => {
  await loadDarePolicy();
  await seedMutualDareUsers();
  const alice = doc(db('alice'), 'dareInvites/one'), bob = doc(db('bob'), 'dareInvites/one');
  await setDoc(alice, invite());
  await assertFails(updateDoc(alice, {opened:true}));
  await assertFails(updateDoc(bob, {dareText:'Changed', opened:true}));
  await assertFails(updateDoc(bob, {senderId:'charlie'}));
  await assertFails(setDoc(alice, invite()));
  await assertSucceeds(updateDoc(bob, {opened:true}));
  await assertFails(updateDoc(bob, {opened:false}));
  await assertSucceeds(deleteDoc(alice)); // Sender account cleanup.
});
test(`${policy}: invitation payloads reject arbitrary metadata, invalid prompts and forged creation dates`, async () => {
  await loadDarePolicy();
  await seedMutualDareUsers();
  for (const value of [{opened:true}, {text:'Chat message'}, {dareText:' '}, {dareText:'x'.repeat(501)},
    {createdAt:Timestamp.fromMillis(1)}, {moodId:null}, {moodName:'x'.repeat(81)}, {mediaUrl:'https://example.com/a.mp4'}]) {
    await assertFails(setDoc(doc(db('alice'), 'dareInvites/one'), invite(value)));
  }
});

}

for (const policy of ['firestore.rules', 'firestore.compat.rules']) {
  const weeklySetup = async () => {
    await env.cleanup();
    env = await initializeTestEnvironment({projectId: 'demo-mooddare',
      firestore: {rules: await readFile(new URL(`../../${policy}`, import.meta.url), 'utf8')},
      storage: {rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8')},
    });
    await env.withSecurityRulesDisabled(async context => {
      await setDoc(doc(context.firestore(), 'weeklyDares/active'), {
        title: 'A little joy', dareText: 'Try a new perspective', moodId: 'happy', moodName: 'Happy',
        startsAt: Timestamp.fromMillis(Date.now() - 86400000), endsAt: Timestamp.fromMillis(Date.now() + 86400000),
      });
      for (const [id, offset] of [['expired', -8], ['future', 8]]) {
        await setDoc(doc(context.firestore(), `weeklyDares/${id}`), {
          title: 'A little joy', dareText: 'Try a new perspective', moodId: 'happy', moodName: 'Happy',
          startsAt: Timestamp.fromMillis(Date.now() + offset * 86400000),
          endsAt: Timestamp.fromMillis(Date.now() + (offset + 7) * 86400000),
        });
      }
    });
  };
  test(`${policy}: weekly schedule is readable only after sign-in and cannot be forged, changed or deleted`, async () => {
    await weeklySetup();
    await assertSucceeds(getDoc(doc(db('alice'), 'weeklyDares/active')));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'weeklyDares/active')));
    await assertFails(setDoc(doc(db('alice'), 'weeklyDares/forged'), {dareText: 'Free credit'}));
    await assertFails(updateDoc(doc(db('alice'), 'weeklyDares/active'), {endsAt: Timestamp.fromMillis(Date.now() + 999999999)}));
    await assertFails(deleteDoc(doc(db('alice'), 'weeklyDares/active')));
    await assertFails(setDoc(doc(db('alice'), 'weeklyDares/active/anything/forged'), {credit: true}));
  });
  test(`${policy}: weekly credit requires a matching post in the server-verified window and is immutable`, async () => {
    await weeklySetup();
    const alice = db('alice'), target = doc(alice, 'posts/one');
    const valid = {...post(), moodId: 'happy', moodName: 'Happy', weeklyDareId: 'active'};
    for (const patch of [
      {weeklyDareId: 'missing'}, {weeklyDareId: 'expired'}, {weeklyDareId: 'future'},
      {weeklyDareId: 1}, {dareText: 'Something else'}, {moodId: 'chill'}, {moodName: 'Chill'},
      {authorId: 'bob'}, {createdAt: Timestamp.fromMillis(0)},
    ]) await assertFails(setDoc(target, {...valid, ...patch}));
    await assertSucceeds(setDoc(target, valid));
    await assertFails(updateDoc(target, {weeklyDareId: 'another-week'}));
    await assertFails(updateDoc(target, {weeklyDareId: null}));
    await assertSucceeds(updateDoc(doc(db('bob'), 'posts/one'), {likedBy: ['bob']}));
    await assertSucceeds(getDocs(query(collection(alice, 'posts'), where('authorId','==','alice'), where('weeklyDareId','==','active'), limit(1))));
    await assertSucceeds(deleteDoc(target));
    // Old clients and late uploads still create ordinary posts without credit.
    await assertSucceeds(setDoc(target, post()));
    await assertFails(updateDoc(target, {weeklyDareId: 'active'}));
  });
}

for (const policy of ['firestore.rules','firestore.compat.rules']) {
  test(`${policy}: profile covers accept only owner-selected presets and remain compatible with legacy profiles`, async () => {
    await env.cleanup();
    env = await initializeTestEnvironment({projectId:'demo-mooddare',
      firestore:{rules:await readFile(new URL(`../../${policy}`,import.meta.url),'utf8')},
      storage:{rules:await readFile(new URL('../../storage.rules',import.meta.url),'utf8')},
    });
    const alice=db('alice'), bob=db('bob'), target=doc(alice,'users/alice');
    await assertSucceeds(setDoc(target,{id:'alice',createdAt:serverTimestamp()}));
    for (const color of ['lavender','midnight','rose','sage','ocean','sunset']) {
      await assertSucceeds(updateDoc(target,{coverColor:color,updatedAt:serverTimestamp()}));
      await assertSucceeds(getDoc(doc(bob,'users/alice')));
    }
    for (const color of ['#ffffff','unknown',123,null,{},'https://image.invalid/cover.jpg']) {
      await assertFails(updateDoc(target,{coverColor:color}));
    }
    await assertFails(updateDoc(doc(bob,'users/alice'),{coverColor:'rose'}));
    await assertFails(setDoc(doc(bob,'users/alice'),{id:'alice',createdAt:serverTimestamp()}));
    await assertFails(deleteDoc(doc(bob,'users/alice')));
    await assertFails(setDoc(doc(bob,'users/other'),{id:'other',createdAt:serverTimestamp(),coverColor:'sage'}));
    await assertFails(updateDoc(doc(env.unauthenticatedContext().firestore(),'users/alice'),{coverColor:'rose'}));
    // An older client can still update normal fields without supplying a cover.
    await assertSucceeds(updateDoc(target,{name:'Alice',updatedAt:serverTimestamp()}));
    await assertSucceeds(deleteDoc(target));
    await assertSucceeds(setDoc(target,{id:'alice',createdAt:serverTimestamp(),coverColor:'ocean'}));
  });
}

for (const policy of ['firestore.rules', 'firestore.compat.rules']) {
  test(`${policy}: notifications are private, server-created, and only read state is editable`, async () => {
    await env.cleanup();
    env = await initializeTestEnvironment({projectId:'demo-mooddare',firestore:{rules:await readFile(new URL(`../../${policy}`,import.meta.url),'utf8')},storage:{rules:await readFile(new URL('../../storage.rules',import.meta.url),'utf8')}});
    const path='users/alice/notifications/n';
    const value={kind:'follow',actorId:'bob',recipientId:'alice',read:false,createdAt:Timestamp.now()};
    await assertFails(setDoc(doc(db('alice'),path),value));
    await assertFails(setDoc(doc(db('bob'),path),value));
    await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),path),value));
    await assertSucceeds(getDoc(doc(db('alice'),path)));
    await assertFails(getDoc(doc(db('bob'),path)));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),path)));
    await assertSucceeds(getDocs(query(collection(db('alice'),'users/alice/notifications'),orderBy('createdAt','desc'),limit(40))));
    await assertSucceeds(updateDoc(doc(db('alice'),path),{read:true}));
    await assertFails(updateDoc(doc(db('alice'),path),{read:false}));
    for(const change of [{actorId:'alice'},{kind:'dare'},{postId:'fake'},{createdAt:serverTimestamp()},{pushAttempted:false}]) await assertFails(updateDoc(doc(db('alice'),path),change));
    await assertFails(deleteDoc(doc(db('bob'),path)));
    await assertSucceeds(deleteDoc(doc(db('alice'),path)));
  });
  test(`${policy}: notification preferences validate keys, types and ownership`,async()=>{
    const path='users/alice/preferences/notifications';
    await assertSucceeds(setDoc(doc(db('alice'),path),{follows:false,likes:true,comments:false,dares:true,weeklyDares:false,push:false}));
    await assertFails(getDoc(doc(db('bob'),path)));
    await assertFails(updateDoc(doc(db('bob'),path),{push:true}));
    await assertFails(updateDoc(doc(db('alice'),path),{likes:'true'}));
    await assertFails(updateDoc(doc(db('alice'),path),{weeklyDares:'true'}));
    await assertFails(setDoc(doc(db('alice'),'notificationCampaigns/2026-10-05'),{complete:false}));
    await assertFails(getDoc(doc(db('alice'),'notificationCampaigns/2026-10-05')));
    await assertFails(updateDoc(doc(db('alice'),path),{token:'private'}));
    await assertSucceeds(deleteDoc(doc(db('alice'),path)));
  });
  test(`${policy}: secret device tokens bind to one signed-in account and cannot be read or listed`,async()=>{
    const path=`pushTokens/${'secret'.repeat(12)}`;
    await assertFails(setDoc(doc(db('alice'),path),{uid:'bob',updatedAt:serverTimestamp()}));
    await assertSucceeds(setDoc(doc(db('alice'),path),{uid:'alice',updatedAt:serverTimestamp()}));
    await assertFails(getDoc(doc(db('alice'),path)));
    await assertFails(getDocs(collection(db('alice'),'pushTokens')));
    await assertFails(deleteDoc(doc(db('bob'),path)));
    await assertFails(updateDoc(doc(db('alice'),path),{other:'anything'}));
    // Only the installation that knows its secret token can rebind it on login.
    await assertSucceeds(setDoc(doc(db('bob'),path),{uid:'bob',updatedAt:serverTimestamp()}));
    await assertFails(deleteDoc(doc(db('alice'),path)));
    await assertSucceeds(deleteDoc(doc(db('bob'),path)));
    await assertFails(setDoc(doc(env.unauthenticatedContext().firestore(),path),{uid:'bob',updatedAt:serverTimestamp()}));
  });
}

for (const policy of ['firestore.rules','firestore.compat.rules']) {
  test(`${policy}: moderation records cannot be forged, read or deleted by app clients`,async()=>{
    await env.cleanup();env=await initializeTestEnvironment({projectId:'demo-mooddare',firestore:{rules:await readFile(new URL(`../../${policy}`,import.meta.url),'utf8')},storage:{rules:await readFile(new URL('../../storage.rules',import.meta.url),'utf8')}});
    for(const c of ['moderationStaff','moderationContent','moderationActions','moderationLocks','moderationReviews','accountRestrictions','analyticsConfig','analyticsDaily','analyticsReceipts','users/alice/analyticsReceipts','users/alice/analyticsState','users/alice/productMetrics','productDaily','productCohorts','websiteDaily','analyticsPresence','analyticsTraffic','analyticsVisits','analyticsPublications','analyticsExclusions']){
      await env.withSecurityRulesDisabled(ctx=>setDoc(doc(ctx.firestore(),`${c}/secret`),{enabled:true}));
      for(const path of [`${c}/secret`,`${c}/secret/nested/item`]){
        await assertFails(getDoc(doc(db('alice'),path)));await assertFails(setDoc(doc(db('alice'),path),{enabled:true}));await assertFails(deleteDoc(doc(db('alice'),path)));
      }
    }
    await assertFails(setDoc(doc(db('alice'),'moderationPosts/one'),{removed:true}));
    await assertFails(getDocs(collection(db('alice'),'moderationPosts')));
  });
  test(`${policy}: banned accounts cannot use existing tokens; expired suspensions recover`,async()=>{
    await setDoc(doc(db('alice'),'posts/one'),post());
    await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),'accountRestrictions/alice'),{status:'banned',until:null}));
    await assertFails(getDoc(doc(db('alice'),'posts/one')));await assertFails(updateDoc(doc(db('alice'),'posts/one'),{likedBy:['alice']}));
    await assertFails(setDoc(doc(db('alice'),'reports/alice_one'),{postId:'one',reporterId:'alice',reason:'inappropriate',createdAt:serverTimestamp()}));
    await assertSucceeds(getDoc(doc(db('alice'),'accountRestrictions/alice')));
    await assertFails(getDoc(doc(db('bob'),'accountRestrictions/alice')));
    await assertFails(deleteDoc(doc(db('alice'),'accountRestrictions/alice')));
    await assertSucceeds(getDoc(doc(db('bob'),'posts/one')));
    await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),'accountRestrictions/alice'),{status:'suspended',until:Timestamp.fromMillis(Date.now()+86400000)}));
    await assertFails(getDoc(doc(db('alice'),'posts/one')));
    await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),'accountRestrictions/alice'),{until:Timestamp.fromMillis(0)}));
    await assertSucceeds(getDoc(doc(db('alice'),'posts/one')));
  });
  test(`${policy}: removed posts cannot be recreated and their storage cannot be fetched or overwritten`,async()=>{
    const storage=env.authenticatedContext('alice').storage();const object=ref(storage,'posts/alice/one.jpg');
    await assertSucceeds(uploadBytes(object,new Uint8Array([1]),{contentType:'image/jpeg'}));
    await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),'moderationPosts/one'),{removed:true}));
    await assertFails(setDoc(doc(db('alice'),'posts/one'),post()));
    await assertFails(uploadBytes(object,new Uint8Array([2]),{contentType:'image/jpeg'}));
    const {getBytes}=await import('firebase/storage');await assertFails(getBytes(object));
    await assertSucceeds(getDoc(doc(db('bob'),'moderationPosts/one')));
    await env.withSecurityRulesDisabled(c=>deleteDoc(doc(c.firestore(),'moderationPosts/one')));
    await assertSucceeds(setDoc(doc(db('alice'),'posts/one'),post()));
    await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),'accountRestrictions/alice'),{status:'banned'}));
    await assertFails(uploadBytes(ref(storage,'posts/alice/two.jpg'),new Uint8Array([1]),{contentType:'image/jpeg'}));
    await assertFails(getBytes(object));
  });
  test(`${policy}: comment/reply reports validate targets and identity and remain private`,async()=>{
    await setDoc(doc(db('alice'),'posts/one'),post());
    await setDoc(doc(db('alice'),'posts/one/comments/c'),{authorId:'alice',text:'Hello',createdAt:serverTimestamp()});
    await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),'posts/one/replies/r'),{authorId:'alice',rootAuthorId:'alice',parentId:'c',text:'Reply',createdAt:Timestamp.now()}));
    for(const [isReply,commentId,type] of [[false,'c','comment'],[true,'r','reply']]){
      const path=`reports/bob_${type}_one_${commentId}`,value={postId:'one',commentId,isReply,reporterId:'bob',reason:'harassment',createdAt:serverTimestamp()};
      await assertSucceeds(setDoc(doc(db('bob'),path),value));await assertFails(getDoc(doc(db('alice'),path)));
      await assertFails(updateDoc(doc(db('bob'),path),{reason:'invalid',createdAt:serverTimestamp()}));
      await assertFails(setDoc(doc(db('alice'),path),value));
      await assertFails(updateDoc(doc(db('bob'),path),{commentId:'missing',createdAt:serverTimestamp()}));
    }
  });
  test(`${policy}: removed comment text cannot be edited or liked`,async()=>{
    await setDoc(doc(db('alice'),'posts/one'),post());
    await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),'posts/one/comments/c'),{authorId:'alice',text:'Removed',moderationRemoved:true,createdAt:Timestamp.now(),likedBy:[]}));
    await assertFails(updateDoc(doc(db('alice'),'posts/one/comments/c'),{text:'Resurrected',editedAt:serverTimestamp()}));
    await assertFails(updateDoc(doc(db('bob'),'posts/one/comments/c'),{likedBy:['bob']}));
    await assertSucceeds(getDoc(doc(db('bob'),'posts/one/comments/c')));
  });
}

for (const policy of ['firestore.rules', 'firestore.compat.rules']) {
  test(`${policy}: reviewed dare catalog is readable but cannot be rewritten by clients`, async () => {
    await env.cleanup();
    env = await initializeTestEnvironment({projectId: 'demo-mooddare',
      firestore: {rules: await readFile(new URL(`../../${policy}`, import.meta.url), 'utf8')},
      storage: {rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8')},
    });
    await env.withSecurityRulesDisabled(async context => {
      await setDoc(doc(context.firestore(), 'dares/relaxed'), {moodName: 'Relaxed', pack: 'basic', dareList: ['Take a photo.']});
    });
    const alice = db('alice');
    await assertSucceeds(getDoc(doc(alice, 'dares/relaxed')));
    await assertSucceeds(getDocs(collection(alice, 'dares')));
    await assertFails(updateDoc(doc(alice, 'dares/relaxed'), {dareList: ['Unreviewed prompt']}));
    await assertFails(deleteDoc(doc(alice, 'dares/relaxed')));
    await assertFails(setDoc(doc(alice, 'dares/new'), {moodName: 'New', dareList: ['Unreviewed']}));
    await assertFails(setDoc(doc(alice, 'dares/relaxed/overrides/new'), {dareList: ['Bypass']}));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'dares/relaxed')));
  });
}

for (const policy of ['firestore.rules','firestore.compat.rules']) {
  test(`${policy}: migrated profiles allow editing, renaming and account cleanup without exposing email or permitting takeover`, async () => {
    await env.cleanup();
    env = await initializeTestEnvironment({projectId:'demo-mooddare',firestore:{rules:await readFile(new URL(`../../${policy}`,import.meta.url),'utf8')},storage:{rules:await readFile(new URL('../../storage.rules',import.meta.url),'utf8')}});
    const alice=db('alice'), bob=db('bob');
    const create=writeBatch(alice);
    create.set(doc(alice,'users/alice'),{id:'alice',name:'Alice',username:'Alice',username_lower:'alice',createdAt:serverTimestamp()});
    create.set(doc(alice,'usernames/alice'),{uid:'alice'});
    await assertSucceeds(create.commit());
    await assertSucceeds(updateDoc(doc(alice,'users/alice'),{bio:'New bio',photoUrl:'https://example.invalid/avatar.jpg',coverColor:'rose',updatedAt:serverTimestamp()}));
    const publicProfile=await assertSucceeds(getDoc(doc(bob,'users/alice')));
    if ('email' in publicProfile.data()) throw Error('Public email exposed');
    for(const fields of [{name:'Impersonated'},{bio:'Changed'},{photoUrl:'https://example.invalid/fake.jpg'},{username:'Stolen',username_lower:'stolen'}]) await assertFails(updateDoc(doc(bob,'users/alice'),fields));
    for(const fields of [{email:'private@example.invalid'},{id:'bob'},{admin:true},{createdAt:serverTimestamp()},{name:'x'.repeat(51)},{bio:'x'.repeat(161)},{photoUrl:'http://example.invalid/avatar.jpg'}]) await assertFails(updateDoc(doc(alice,'users/alice'),fields));
    await assertFails(deleteDoc(doc(bob,'users/alice')));
    await assertFails(deleteDoc(doc(bob,'usernames/alice')));
    await assertFails(setDoc(doc(bob,'usernames/alice'),{uid:'bob'}));
    await assertFails(getDocs(collection(bob,'usernames')));
    await assertFails(updateDoc(doc(alice,'users/alice'),{username:'Alice_new',username_lower:'alice_new'}));
    const rename=writeBatch(alice);
    rename.update(doc(alice,'users/alice'),{username:'Alice_new',username_lower:'alice_new',updatedAt:serverTimestamp()});
    rename.set(doc(alice,'usernames/alice_new'),{uid:'alice'});
    rename.delete(doc(alice,'usernames/alice'));
    await assertSucceeds(rename.commit());
    const remove=writeBatch(alice);
    remove.delete(doc(alice,'usernames/alice_new'));
    remove.delete(doc(alice,'users/alice'));
    await assertSucceeds(remove.commit());
    await assertSucceeds(getDoc(doc(bob,'users/alice')));
  });
  test(`${policy}: unknown root and nested collections fail closed, including signed-in owners`,async()=>{
    await env.cleanup();
    env=await initializeTestEnvironment({projectId:'demo-mooddare',firestore:{rules:await readFile(new URL(`../../${policy}`,import.meta.url),'utf8')},storage:{rules:await readFile(new URL('../../storage.rules',import.meta.url),'utf8')}});
    for(const target of ['unreviewed/x','users/alice/private/x','users/alice/preferences/unknown']){
      await env.withSecurityRulesDisabled(ctx=>setDoc(doc(ctx.firestore(),target),{secret:'private'}));
      for(const uid of ['alice','bob']){
        const ref=doc(db(uid),target);
        await assertFails(getDoc(ref));await assertFails(setDoc(ref,{secret:'changed'}));await assertFails(deleteDoc(ref));
      }
    }
  });
}

test('accepted account deletion blocks all writes and uploads, with private server-owned job status', async () => {
  await env.withSecurityRulesDisabled(async c => {
    const f=c.firestore();
    await setDoc(doc(f,'users/alice'),{id:'alice'});
    await setDoc(doc(f,'posts/one'),post());
    await setDoc(doc(f,'posts/one/comments/root'),{authorId:'alice',text:'root',createdAt:Timestamp.now(),likedBy:[]});
    await setDoc(doc(f,'accountDeletions/alice'),{status:'pending'});
    await setDoc(doc(f,'accountRestrictions/alice'),{status:'deleting'});
  });
  await assertSucceeds(getDoc(doc(db('alice'),'accountDeletions/alice')));
  await assertFails(getDoc(doc(db('bob'),'accountDeletions/alice')));
  await assertFails(setDoc(doc(db('alice'),'accountDeletions/alice'),{status:'complete'}));
  await assertFails(deleteDoc(doc(db('alice'),'accountDeletions/alice')));
  await assertFails(updateDoc(doc(db('alice'),'users/alice'),{bio:'recreate'}));
  await assertFails(setDoc(doc(db('alice'),'posts/two'),{...post(),mediaPath:'posts/alice/two.jpg'}));
  await assertFails(setDoc(doc(db('bob'),'posts/one/comments/new'),{authorId:'bob',text:'late comment',createdAt:serverTimestamp(),likedBy:[]}));
  await assertFails(setDoc(doc(db('bob'),'users/bob/blocked/alice'),{createdAt:serverTimestamp()}));
  await assertFails(uploadBytes(ref(env.authenticatedContext('alice').storage(),'posts/alice/late.jpg'),new Uint8Array([1]),{contentType:'image/jpeg'}));
  await assertSucceeds(uploadBytes(ref(env.authenticatedContext('bob').storage(),'posts/bob/live.jpg'),new Uint8Array([1]),{contentType:'image/jpeg'}));
});
test('an abandoned-upload fence prevents a late post commit and storage overwrite',async()=>{
  await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),'moderationPosts/one'),{removed:true,reason:'abandoned-upload',ownerId:'alice',replacementPostId:'replacement'}));
  await assertFails(setDoc(doc(db('alice'),'posts/one'),post()));
  await assertFails(uploadBytes(ref(env.authenticatedContext('alice').storage(),'posts/alice/one.jpg'),new Uint8Array([1]),{contentType:'image/jpeg'}));
  await assertSucceeds(setDoc(doc(db('alice'),'posts/replacement'),{...post(),mediaPath:'posts/alice/replacement.jpg'}));
});

test('personalization history is owner-only and validates post identity and retention', async () => {
  await setDoc(doc(db('alice'), 'posts/one'), post());
  const data = {authorId:'alice', moodId:null, viewed:true, completed:false, liked:false, saved:false, notInterested:false, updatedAt:serverTimestamp(), expiresAt:Timestamp.fromMillis(Date.now()+30*86400000)};
  const history = doc(db('bob'), 'users/bob/feedHistory/one');
  await assertSucceeds(setDoc(history, data));
  await assertSucceeds(getDoc(history));
  await assertFails(getDoc(doc(db('alice'), 'users/bob/feedHistory/one')));
  await assertFails(getDocs(collection(db('alice'), 'users/bob/feedHistory')));
  await assertFails(setDoc(doc(db('alice'), 'users/bob/feedHistory/one'), data));
  for (const changes of [{authorId:'invented'}, {moodId:'invented'}, {viewed:3}, {score:100}, {expiresAt:Timestamp.fromMillis(Date.now()+32*86400000)}, {updatedAt:Timestamp.fromMillis(1)}]) {
    await assertFails(setDoc(history, {...data,...changes}));
  }
  await assertFails(setDoc(doc(db('bob'), 'users/bob/feedHistory/missing'), data));
  await assertFails(setDoc(doc(db('alice'), 'users/alice/feedHistory/one'), data));
  await assertSucceeds(deleteDoc(history));
});
test('feed order is private, constrained and disabled for restricted accounts', async () => {
  const preference=doc(db('bob'),'users/bob/preferences/feed');
  await assertSucceeds(setDoc(preference,{order:'forYou'}));
  await assertSucceeds(setDoc(preference,{order:'latest'}));
  await assertFails(setDoc(preference,{order:'viral'}));
  await assertFails(setDoc(preference,{order:'latest',public:true}));
  await assertFails(getDoc(doc(db('alice'),'users/bob/preferences/feed')));
  await env.withSecurityRulesDisabled(async c => setDoc(doc(c.firestore(),'accountRestrictions/bob'),{status:'deleting'}));
  await assertFails(setDoc(preference,{order:'forYou'}));
});
test('deleted, expired and deleting authors cannot receive new recommendation activity', async () => {
  await setDoc(doc(db('alice'), 'posts/one'), post());
  const value={authorId:'alice',moodId:null,viewed:true,completed:false,liked:false,saved:false,notInterested:false,updatedAt:serverTimestamp(),expiresAt:Timestamp.fromMillis(Date.now()+86400000)};
  const target=doc(db('bob'),'users/bob/feedHistory/one');
  await env.withSecurityRulesDisabled(async c=> updateDoc(doc(c.firestore(),'posts/one'),{deleting:true}));
  await assertFails(setDoc(target,value));
  await env.withSecurityRulesDisabled(async c=> updateDoc(doc(c.firestore(),'posts/one'),{deleting:false,expiresAt:Timestamp.fromMillis(1)}));
  await assertFails(setDoc(target,value));
  await env.withSecurityRulesDisabled(async c=> {await updateDoc(doc(c.firestore(),'posts/one'),{expiresAt:Timestamp.fromMillis(Date.now()+86400000)});await setDoc(doc(c.firestore(),'accountDeletions/alice'),{status:'pending'});});
  await assertFails(setDoc(target,value));
});

test('post share counter is server owned; environment metadata cannot be changed', async()=>{
 const ref=doc(db('alice'),'posts/one');
 await assertFails(setDoc(ref,{...post(),shareCount:10}));
 await assertFails(setDoc(ref,{...post(),analyticsEnvironment:'invalid'}));
 await assertSucceeds(setDoc(ref,{...post(),analyticsEnvironment:'development'}));
 await assertFails(updateDoc(ref,{shareCount:1}));
 await assertFails(updateDoc(ref,{analyticsEnvironment:'production'}));
});
