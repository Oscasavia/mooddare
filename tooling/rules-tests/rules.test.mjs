import { readFile } from 'node:fs/promises';
import { before, after, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp, Timestamp, collection, collectionGroup, query, where, orderBy, getDocs, getCountFromServer } from 'firebase/firestore';
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
    await assertFails(deleteDoc(doc(db('charlie'), 'posts/one/comments/c')));
    await assertSucceeds(deleteDoc(doc(db('alice'), 'posts/one/comments/c')));
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
