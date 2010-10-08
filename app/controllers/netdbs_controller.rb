class NetdbsController < ApplicationController
  def index
    @search = Netdb.search params[:search]
    @netdbs = @search.paginate(:page => params[:page])
  end

  def new
    @netdb = Netdb.new
  end

  def create
    @netdb = Netdb.new(params[:netdb])
    if @netdb.save
      flash[:foreman_notice] = "Successfully created network database"
      redirect_to netdbs_url
    else
      render :action => 'new'
    end
  end

  def edit
    @netdb = Netdb.find(params[:id])
  end

  def update
    @netdb = Netdb.find(params[:id])
    if @netdb.update_attributes(params[:netdb])
      flash[:foreman_notice] = "Successfully updated network database"
      redirect_to netdbs_url
    else
      render :action => 'edit'
    end
  end

  def destroy
    @netdb = Netdb.find(params[:id])
    @netdb.destroy
    flash[:foreman_notice] = "Successfully destroyed network database"
    redirect_to netdbs_url
  end
end
