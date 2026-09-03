# Day 53 Resolving a VolumeMounts Misconfiguration in a Kubernetes Nginx and PHP-FPM Pod

## The real-world problem
A multi-container pod serving a website stopped working, but `kubectl get pods` showed `2/2 Running` with zero restarts. No crash, no CrashLoopBackOff, no obvious Kubernetes event pointing anywhere. In a real on-call scenario this is the kind of status that gets a ticket closed early as a false alarm, right up until someone notices the site is actually broken.

## How I approached it
I treated the healthy pod status as a red flag rather than a green light. A pod being `Running` only means the containers started and stayed alive. It says nothing about whether the application-level wiring between them — shared volumes, config paths, FastCGI routing — is actually correct. I worked through the pod's configuration layer by layer before touching anything.

## Key concepts

**Multi-container pods and shared volumes**
Containers in a pod do not share a filesystem by default. Nginx and PHP-FPM both need access to the same application files, which in Kubernetes is only possible through a `Volume` object mounted into both containers. Here that was an `EmptyDir` volume named `shared-files`.

**Independent mount paths**
Kubernetes lets each container mount the same volume at a different local path. This is legal but dangerous. Any configuration that assumes both containers agree on "the path" will silently break if that assumption is wrong, and nothing in Kubernetes will tell you.

**FastCGI request handoff**
Nginx does not execute PHP. For `.php` requests it proxies to PHP-FPM over FastCGI and passes a `SCRIPT_FILENAME` parameter telling PHP-FPM where to find the script on PHP-FPM's own filesystem, not Nginx's. If those paths disagree, PHP-FPM returns "File not found" even though the file is sitting in the shared volume.

**ConfigMap volume sync lag**
ConfigMaps mounted as volumes are not instantly reflected inside a running pod after an edit. Kubelet syncs them on a periodic interval. Reloading Nginx before that sync completes reloads the old content, which looks like the fix failed when it actually just hasn't landed yet.

## Solution

**Step 1: Confirm pod status**
```
kubectl get pods
```
`2/2 Running`, zero restarts ruled out a startup failure and pointed toward a silent config issue.

**Step 2: Inspect the pod's full wiring**
```
kubectl describe pod nginx-phpfpm
```
The `Mounts:` block under each container revealed the bug. The two containers mounted the same shared volume at different paths:

| Container | Shared volume mount path |
|---|---|
| `nginx-container` | `/var/www/html` |
| `php-fpm-container` | `/usr/share/nginx/html` |

**Step 3: Inspect the ConfigMap**
```
kubectl get configmap nginx-config -o yaml
```
The Nginx config had:
```nginx
root /var/www/html;
fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
```
`$document_root` resolves to Nginx's own `root` value, `/var/www/html`, and that gets forwarded to PHP-FPM as "here's where your script lives." But PHP-FPM's copy of the shared volume is mounted at `/usr/share/nginx/html`. It receives a path that doesn't exist on its own filesystem.

**Step 4: Check pod ownership before deleting anything**
```
kubectl get pod nginx-phpfpm -o jsonpath='{.metadata.ownerReferences}'
```
Empty output confirmed this was a bare pod with no owning Deployment or ReplicaSet. A `kubectl delete` would not self-heal. I saved the spec before touching anything.

**Step 5: Edit the ConfigMap**
```
kubectl edit configmap nginx-config
```
Changed `fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;` to:
```nginx
fastcgi_param SCRIPT_FILENAME /usr/share/nginx/html$fastcgi_script_name;
```
This hardcodes PHP-FPM's actual mount path instead of relying on a variable that only reflects Nginx's own configuration.

**Step 6: Force the fix into the running pod**
```
kubectl get pod nginx-phpfpm -o yaml > /tmp/nginx-phpfpm.yaml
kubectl replace --force -f /tmp/nginx-phpfpm.yaml
```
ConfigMap sync hadn't propagated yet, and most pod spec fields are immutable in place, so recreating from the saved manifest was the right move.

**Step 7: Copy the application file**
```
kubectl cp /home/thor/index.php nginx-phpfpm:/var/www/html/index.php -c nginx-container
```
The destination has to match Nginx's actual mount path. An earlier attempt copied the file to `/usr/share/nginx/html` inside the nginx container, which is just that image's unrelated local default directory and completely disconnected from the shared volume.

## How to verify this actually works
Check both containers see the same file through the shared volume:
```
kubectl exec nginx-phpfpm -c nginx-container   -- ls -l /var/www/html/
kubectl exec nginx-phpfpm -c php-fpm-container -- ls -l /usr/share/nginx/html/
```
Same file, same size, same timestamp on both sides confirms the shared volume is working. Then hit the Website button and look for a full `phpinfo()` page. The definitive check inside that page is `$_SERVER['SCRIPT_FILENAME']` resolving to `/usr/share/nginx/html/index.php`, which confirms PHP-FPM is using its own mount path, not Nginx's.

## Common mistakes here

Checking only one container's filesystem and assuming the other matches. That assumption is exactly how this kind of bug ships.

Reloading Nginx right after editing the ConfigMap and concluding the fix failed because the config inside the container still shows the old value. The edit may have saved fine. The file inside the pod just hasn't synced yet.

Deleting the pod without checking ownership first. A bare pod does not self-heal. Always run the `ownerReferences` check before `kubectl delete`.

Copying the application file to the wrong path. The shared volume is only accessible at the specific mount path defined in the pod spec, not at whatever directory looks like a document root in the image.

## Transferable pattern
Whenever two processes need to share files in Kubernetes, verify both containers' mount paths before writing any config that references those paths. The volume name matches in the spec, but the local paths inside each container can be completely different. Any config value that crosses a container boundary needs to be verified from the receiving container's perspective, not the sender's.

## What I learned

The most important thing this task reinforced was that a healthy pod status is not the same as a working application. I knew this in theory but running into it in practice made it concrete. The instinct to check `kubectl get pods`, see `2/2 Running`, and move on is strong, and it's wrong.

The ConfigMap sync lag was something I had to actually encounter to internalize. I edited the ConfigMap, reloaded Nginx, checked the live config inside the container, saw the old value, and for a moment thought my edit hadn't saved. Checking the ConfigMap object directly confirmed it had. That gap between "the edit saved" and "the edit is live inside the pod" is easy to confuse under pressure and easy to fix once you know to look for it.

The `ownerReferences` check before deleting anything is now a permanent habit. Spending five seconds on that command is a lot cheaper than explaining why the pod is gone and there's no manifest to bring it back.
