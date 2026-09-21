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
