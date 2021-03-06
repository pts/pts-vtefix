#! /bin/sh --
#
# vtefix.sh: fix consistency of <Z> and Ctrl-<Z> in GNOME Terminal
# by pts@fazekas.hu at Thu Dec 31 18:05:42 CET 2009
#
# Usage: sudo ./vtefix.sh
#
# Problem this script fixes: In GNOME Terminal, with the Hungarian and
# German keyboard layouts the keys Y and Z are switched with respect to the
# US English layout. So when the national layout active, one of the keys
# yields the string "z", but when the same key is pressed with Ctrl, it
# yields "^Y", instead of the expected ("^Z"). All other applications (e.g.
# GIMP, Firefox, xterm) work as expected, except for those using VTE (e.g.
# GNOME Terminal)
#
# More information about the problem:
#
# * http://bugzilla.gnome.org/show_bug.cgi?id=575883
# * http://bugzilla.gnome.org/show_bug.cgi?id=375112
#
# In vte-0.16.3/src/vte.c (Ubuntu Hardy /usr/lib/libvte.so.9.2.17):
#
#        if (handled == FALSE && normal == NULL && special == NULL) {
#                if (event->group &&
#                                (terminal->pvt->modifiers & GDK_CONTROL_MASK)) 
#                        keyval = vte_translate_national_ctrlkeys(event);
#                keychar = gdk_keyval_to_unicode(keyval);
#
# Below we replace GDK_CONTROL_MASK (== 4) by 0, so the condition is
# always false. The relevant disassembly dump is:
#
# amd64 Ubuntu Hardy:
# $ objdump -d /usr/lib/libvte.so.9.2.17 | grep testb | grep '[$]0x4,'
# 2a786:       f6 80 88 0a 00 00 04    testb  $0x4,0xa88(%rax)
# 2a7ba:       f6 87 88 0a 00 00 04    testb  $0x4,0xa88(%rdi)
# 
# i386 Ubuntu Hardy:
# $ objdump -d /usr/lib/libvte.so.9.2.17 | grep testb | grep '[$]0x4,'
# 25cd8:       f6 80 4c 09 00 00 04    testb  $0x0,0x94c(%eax)
# 25d0d:       f6 81 4c 09 00 00 04    testb  $0x4,0x94c(%ecx)
#
# i386 Ubuntu Karmic (similar for Lucid):
# 2b7b0:       8b 80 84 09 00 00       mov    0x984(%eax),%eax
# 2b7b6:       89 85 7c ff ff ff       mov    %eax,-0x84(%ebp)
# ...
# 2b9ed:	f6 85 7c ff ff ff 04 	testb  $0x4,-0x84(%ebp)
# 2bad9:	f6 85 7c ff ff ff 04 	testb  $0x4,-0x84(%ebp)
# 2bcbe:	f6 85 7c ff ff ff 04 	testb  $0x4,-0x84(%ebp)  # to fix
# 2bcf5:	f6 85 7c ff ff ff 04 	testb  $0x4,-0x84(%ebp)
#
# x86_64 Ubuntu Lucid:
# 30402:       e9 d6 fa ff ff          jmpq   2fedd <vte_terminal_set_color_bold+0x39bd>
# 30407:       80 7d 32 00             cmpb   $0x0,0x32(%rbp)
# 3040b:       74 11                   je     3041e <vte_terminal_set_color_bold+0x3efe>
# 3040d:       41 f6 c5 04             test   $0x4,%r13b  # to fix
# 30411:       0f 1f 80 00 00 00 00    nopl   0x0(%rax)
# 30418:       0f 85 ee 03 00 00       jne    3080c <vte_terminal_set_color_bold+0x42ec>
#
# To find the spot to patch, grep for gdk_keyval_to_unicode in the output of
# `objdump -d /usr/lib/libvte.so.9'.

exec perl -we '
  use integer;
  use strict;
  my $fn = $ARGV[0];
  print STDERR "info: vtefix library filename: $fn\n";
  die "error: file not found: $fn\n" if !open F, "<", $fn;
  $_ = join "", <F>;
  my @L;
  while (/\xf6[\x80-\x8f].[\x09-\x0a]\0\0[\x00\x04]
         |\x80[\x78-\x7f].\0\x74.\xf6\x85.\xff\xff\xff[\x00\x04]
         |\x80\x7d\x32\x00\x74\x11\x41\xf6\xc5[\x00\x04]
          (?=(?:\x0f\x1f\x80\0\0\0\0)?\x0f\x85)
         /sgx) {
    push @L, pos($_) - 1;  # offset of the last [\x00\x04]
  }
  # We patch only the first occurrence, the 2nd one is different.
  pop @L if @L == 2 and vec($_, $L[0] - 6, 8) == 0xf6 and
                        vec($_, $L[1] - 6, 8) == 0xf6;
  if (@L == 1) {
    if (vec($_, $L[0], 8) == 4) {  # need to patch
      print "info: patching at offset $L[0]\n";
      die "error: cannot open file for writing: $fn\n" if !open F, "+<", $fn;
      die if !sysseek F, $L[0], 0;
      die if !syswrite F, "\0";
      print "info: patching OK, no need to restart gnome-terminal\n";
    } else {
      print "info: already patched at offset $L[0]\n";
      exit 2;
    }
  } else {
    die "error: instruction to patch not found (@L)\n";
  }
' -- "${1:-/usr/lib/libvte.so.9}"
