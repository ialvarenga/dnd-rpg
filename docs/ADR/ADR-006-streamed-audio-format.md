# ADR-006: Shipped audio is Ogg Vorbis, not WAV

## Status

Accepted.

## Decision

Every audio file committed under `godot/assets/` is stored in a compressed
format. Music is Ogg Vorbis, encoded with:

    ffmpeg -i <master>.wav -c:a libvorbis -q:a 5 <track>.ogg

Uncompressed masters are not committed. If a track has to be re-encoded, the
master is fetched from wherever it is archived, re-encoded with the command
above, and only the `.ogg` lands in the repository. `godot/assets/music/*.wav`
is gitignored so a master cannot be committed by accident.

## Consequences

Godot imports `.wav` as `AudioStreamWAV`, which is decoded in full into memory,
and `.ogg` as `AudioStreamOggVorbis`, which streams. For multi-minute ambient
and battle loops the streamed form is the correct runtime choice regardless of
repository size, so this is not purely a storage decision.

The four shipped tracks went from 80 MB of WAV to 8.5 MB of Ogg at `-q:a 5`,
with no audible loss at the volumes music plays at under combat SFX. That keeps
the whole working tree small enough that the project needs neither Git LFS nor
an external asset bucket; both were considered and rejected as machinery this
project does not yet earn. A bucket becomes the right answer only if
uncompressed masters or other large source files (`.blend`, layered textures)
ever need to be versioned — those belong outside the repository, with the
repository holding only the derived, game-ready asset.

Short one-shot SFX are exempt from the Ogg rule: WAV is a defensible choice
there because decode-on-load cost matters more than file size for sounds of a
second or two. The `.wav` ignore is therefore scoped to `assets/music/`.
