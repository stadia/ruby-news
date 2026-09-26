# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

class BlogsController < ApplicationController
  include WebOnlyFormats
  include PostViewing

  skip_before_action :authenticate_user!, only: [ :show ]

  # GET /@:username/blog/:slug — public blog detail. Scopes by username so the
  # URL is canonical, but slugs are globally unique so this never ambiguates.
  # 대소문자·NFD로 달라진 slug는 같은 글을 찾아 표준 URL로 301 리다이렉트한다.
  def show
    user = User.find_by!(username: params[:username])
    post = user.posts.blog.includes(POST_SHOW_INCLUDES)
               .find_by!(slug: BlogSlug.lookup_key(params[:slug]))
    if post.slug != params[:slug]
      return redirect_to user_profile_blog_post_url(username: user.username, slug: post), status: :moved_permanently
    end

    render_post_show(post)
  end
end
